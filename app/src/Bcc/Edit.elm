module Bcc.Edit exposing (Msg, Model, update, view, init)

import Browser.Navigation as Nav

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col
import Bootstrap.Form as Form
import Bootstrap.Form.Input as Input
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Form.Radio as Radio
import Bootstrap.Button as Button
import Bootstrap.ListGroup as ListGroup


import Url

import Set
import Http
import Json.Encode as Encode
import Json.Decode exposing (Decoder, map2, field, string, int, at, nullable, list)
import Json.Decode.Pipeline as JP


import Route
import Bcc

-- MODEL

type alias EditingCanvas = 
  { canvas : Bcc.BoundedContextCanvas
  , addingMessage : AddingMessage
  }
type alias AddingMessage = 
  { commandsHandled : Bcc.Command
  , commandsSent : Bcc.Command
  , eventsHandled : Bcc.Event
  , eventsPublished : Bcc.Event
  , queriesHandled : Bcc.Query
  , queriesInvoked : Bcc.Query
  }

type alias Model = 
  { key: Nav.Key
  , self: Url.Url
  -- TODO: discuss we want this in edit or BCC - it's not persisted after all!
  , edit: EditingCanvas
  }

initAddingMessage = 
  { commandsHandled = ""
  , commandsSent = ""
  , eventsHandled = ""
  , eventsPublished = ""
  , queriesHandled = ""
  , queriesInvoked = ""
  }

init : Nav.Key -> Url.Url -> (Model, Cmd Msg)
init key url =
  let
    model =
      { key = key
      , self = url
      , edit = 
        { addingMessage = initAddingMessage
        , canvas = Bcc.init ()
        }
      }
  in
    (
      model
    , loadBCC model
    )


-- UPDATE

type MessageFieldMsg
  = CommandsHandled String

type EditingMsg
  = Field Bcc.Msg
  | MessageField MessageFieldMsg

type Msg
  = Loaded (Result Http.Error Bcc.BoundedContextCanvas)
  | Editing EditingMsg
  | Save
  | Saved (Result Http.Error ())
  | Delete
  | Deleted (Result Http.Error ())
  | Back

updateAddingMessage : MessageFieldMsg -> AddingMessage -> AddingMessage
updateAddingMessage msg model =
  case msg of
    CommandsHandled cmd ->
      { model | commandsHandled = cmd}

updateEdit : EditingMsg -> EditingCanvas -> EditingCanvas
updateEdit msg model =
  case msg of
    Field (Bcc.ChangeMessages change) ->
      let
        addingMessageModel = model.addingMessage
        addingMessage = 
          case change of
            Bcc.AddCommandHandled _ ->
              { addingMessageModel | commandsHandled = "" }
            _ -> addingMessageModel
      in
        { model | canvas = Bcc.update (Bcc.ChangeMessages change) model.canvas, addingMessage = addingMessage }
    Field fieldMsg ->
        { model | canvas = Bcc.update fieldMsg model.canvas }
    MessageField fieldMsg ->
      { model | addingMessage = updateAddingMessage fieldMsg model.addingMessage }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Editing editing ->
      ({ model | edit = updateEdit editing model.edit}, Cmd.none)
    Save -> 
      (model, saveBCC model)
    Saved (Ok _) -> 
      (model, Cmd.none)
    Delete ->
      (model, deleteBCC model)
    Deleted (Ok _) ->
      (model, Route.pushUrl Route.Overview model.key)
    Loaded (Ok m) ->
      let
        editing = { canvas = m, addingMessage = initAddingMessage }
      in
        ({ model | edit = editing } , Cmd.none)    
    Back -> 
      (model, Route.goBack model.key)
    _ ->
      Debug.log ("BCC: " ++ Debug.toString msg ++ " " ++ Debug.toString model)
      (model, Cmd.none)

-- VIEW

view : Model -> Html Msg
view model =
  div []
      [ viewCanvas model.edit |> Html.map Editing
      , Grid.row []
        [ Grid.col [] 
          [ Button.button [Button.secondary, Button.onClick Back] [text "Back"]
          , Button.submitButton [ Button.primary, Button.onClick Save ] [ text "Save"]
          , Button.button 
            [ Button.danger
            , Button.small
            , Button.onClick Delete
            , Button.attrs [ title ("Delete " ++ model.edit.canvas.name) ] 
            ]
            [ text "X" ]
          ]
        ]
      ]

viewRadioButton : String -> String -> Bool -> Bcc.Msg -> Radio.Radio Bcc.Msg
viewRadioButton id title checked msg =
  Radio.create [Radio.id id, Radio.onClick msg, Radio.checked checked] title

viewLeftside : Bcc.BoundedContextCanvas -> List (Html EditingMsg)
viewLeftside model =
  [ Form.group []
    [ Form.label [for "name"] [ text "Name"]
    , Input.text [ Input.id "name", Input.value model.name, Input.onInput Bcc.SetName ] ]
  , Form.group []
    [ Form.label [for "description"] [ text "Description"]
    , Input.text [ Input.id "description", Input.value model.description, Input.onInput Bcc.SetDescription ]
    , Form.help [] [ text "Summary of purpose and responsibilities"] ]
  , Grid.row []
    [ Grid.col [] 
      [ Form.label [for "classification"] [ text "Bounded Context classification"]
      , div [] 
          (Radio.radioList "classification" 
          [ viewRadioButton "core" "Core" (model.classification == Just Bcc.Core) (Bcc.SetClassification Bcc.Core) 
          , viewRadioButton "supporting" "Supporting" (model.classification == Just Bcc.Supporting) (Bcc.SetClassification Bcc.Supporting) 
          , viewRadioButton "generic" "Generic" (model.classification == Just Bcc.Generic) (Bcc.SetClassification Bcc.Generic) 
          -- TODO: Other
          ]
          )
      , Form.help [] [ text "How can the Bounded Context be classified?"] ]
      , Grid.col []
        [ Form.label [for "businessModel"] [ text "Business Model"]
        , div [] 
            (Radio.radioList "businessModel" 
            [ viewRadioButton "revenue" "Revenue" (model.businessModel == Just Bcc.Revenue) (Bcc.SetBusinessModel Bcc.Revenue) 
            , viewRadioButton "engagement" "Engagement" (model.businessModel == Just Bcc.Engagement) (Bcc.SetBusinessModel Bcc.Engagement) 
            , viewRadioButton "Compliance" "Compliance" (model.businessModel == Just Bcc.Compliance) (Bcc.SetBusinessModel Bcc.Compliance) 
            , viewRadioButton "costReduction" "Cost reduction" (model.businessModel == Just Bcc.CostReduction) (Bcc.SetBusinessModel Bcc.CostReduction) 
            -- TODO: Other
            ]
            )
        , Form.help [] [ text "What's the underlying business model of the Bounded Context?"] ]
      , Grid.col []
        [ Form.label [for "evolution"] [ text "Evolution"]
        , div [] 
            (Radio.radioList "evolution" 
            [ viewRadioButton "genesis" "Genesis" (model.evolution == Just Bcc.Genesis) (Bcc.SetEvolution Bcc.Genesis) 
            , viewRadioButton "customBuilt" "Custom built" (model.evolution == Just Bcc.CustomBuilt) (Bcc.SetEvolution Bcc.CustomBuilt) 
            , viewRadioButton "product" "Product" (model.evolution == Just Bcc.Product) (Bcc.SetEvolution Bcc.Product) 
            , viewRadioButton "commodity" "Commodity" (model.evolution == Just Bcc.Commodity) (Bcc.SetEvolution Bcc.Commodity) 
            -- TODO: Other
            ]
            )
        , Form.help [] [ text "How does the context evolve? How novel is it?"] ]
    ]
  , Form.group []
    [ Form.label [for "businessDecisions"] [ text "Business Decisions"]
      , Textarea.textarea [ Textarea.id "businessDecisions", Textarea.rows 4, Textarea.value model.businessDecisions, Textarea.onInput Bcc.SetBusinessDecisions ]
      , Form.help [] [ text "Key business rules, policies and decisions"] ]
  , Form.group []
    [ Form.label [for "ubiquitousLanguage"] [ text "Ubiquitous Language"]
      , Textarea.textarea [ Textarea.id "ubiquitousLanguage", Textarea.rows 4, Textarea.value model.ubiquitousLanguage, Textarea.onInput Bcc.SetUbiquitousLanguage ]
      , Form.help [] [ text "Key domain terminology"] ]
  ]
  |> List.map (Html.map Field)

viewMessageOption : (Bcc.Message -> Bcc.MessageMsg) -> Bcc.Message -> ListGroup.Item Bcc.MessageMsg
viewMessageOption remove model =
  ListGroup.li [] 
    [ Button.button [Button.danger, Button.onClick (remove model)] [ text "x"]
    , text model
    ]

viewMessages : EditingCanvas -> Html EditingMsg
viewMessages editing =
  let
    messages = editing.canvas.messages
  in
  div []
    [ Html.h5 [] [ text "Messages Consumed and Produced" ]
    , Grid.row []
      [ Grid.col [] 
        [ Html.h6 [] [ text "Messages Consumed"]
        , Form.group []
          [ Form.label [for "commandsHandled"] [ text "Commands handled"]
          , ListGroup.ul 
            (
              messages.commandsHandled
              |> Set.toList
              |> List.map (viewMessageOption Bcc.RemoveCommandHandled)
            )
            |> Html.map (Bcc.ChangeMessages >> Field)
          , Form.form [Html.Events.onSubmit (editing.addingMessage.commandsHandled |> Bcc.AddCommandHandled |> Bcc.ChangeMessages |> Field)  ]
            [ Input.text 
              [ Input.id "commandHandled"
              , Input.value editing.addingMessage.commandsHandled
              , Input.onInput CommandsHandled 
              ] |> Html.map MessageField
            , Button.submitButton [ Button.secondary] [ text "Add"]
            ]
          ] 
        ]
      , Grid.col []
        [ Html.h6 [] [ text "Messages Consumed"]
        ]
      ]
    ]

viewRightside : EditingCanvas -> List (Html EditingMsg)
viewRightside model =
  [ Form.group []
    [ Form.label [for "modelTraits"] [ text "Model traits"]
    , Input.text [ Input.id "modelTraits", Input.value model.canvas.modelTraits, Input.onInput Bcc.SetModelTraits ] |> Html.map Field
    , Form.help [] [ text "draft, execute, audit, enforcer, interchange, gateway, etc."] ]
    , viewMessages model
  ]

viewCanvas : EditingCanvas -> Html EditingMsg
viewCanvas model =
  Grid.row []
    [ Grid.col [] (viewLeftside model.canvas)
    , Grid.col [] (viewRightside model)
    ]


-- HTTP

loadBCC: Model -> Cmd Msg
loadBCC model =
  Http.get
    { url = Url.toString model.self
    , expect = Http.expectJson Loaded modelDecoder
    }

saveBCC: Model -> Cmd Msg
saveBCC model =
    Http.request
      { method = "PUT"
      , headers = []
      , url = Url.toString model.self
      , body = Http.jsonBody <| modelEncoder model.edit.canvas
      , expect = Http.expectWhatever Saved
      , timeout = Nothing
      , tracker = Nothing
      }

deleteBCC: Model -> Cmd Msg
deleteBCC model =
    Http.request
      { method = "DELETE"
      , headers = []
      , url = Url.toString model.self
      , body = Http.emptyBody
      , expect = Http.expectWhatever Deleted
      , timeout = Nothing
      , tracker = Nothing
      }

-- encoders
        
messagesEncoder : Bcc.Messages -> Encode.Value
messagesEncoder messages =
  Encode.object
    [ ("commandsHandled", Encode.set Encode.string messages.commandsHandled)
    , ("commandsSent", Encode.set Encode.string messages.commandsSent)
    , ("eventsHandled", Encode.set Encode.string messages.eventsHandled)
    , ("eventsPublished", Encode.set Encode.string messages.eventsPublished)
    , ("queriesHandled", Encode.set Encode.string messages.queriesHandled)
    , ("queriesInvoked" , Encode.set Encode.string messages.queriesInvoked)
    ]

modelEncoder : Bcc.BoundedContextCanvas -> Encode.Value
modelEncoder canvas = 
  Encode.object
    [ ("name", Encode.string canvas.name)
    , ("description", Encode.string canvas.description)
    , ("classification", maybeStringEncoder Bcc.classificationToString canvas.classification)
    , ("businessModel", maybeStringEncoder Bcc.businessModelToString canvas.businessModel)
    , ("evolution", maybeStringEncoder Bcc.evolutionToString canvas.evolution)
    , ("businessDecisions", Encode.string canvas.businessDecisions)
    , ("ubiquitousLanguage", Encode.string canvas.ubiquitousLanguage)
    , ("modelTraits", Encode.string canvas.modelTraits)
    , ("messages", messagesEncoder canvas.messages)
    ]

maybeStringEncoder : (t -> String) -> Maybe t -> Encode.Value
maybeStringEncoder encoder value =
  case value of
    Just v -> Encode.string (encoder v)
    Nothing -> Encode.null

maybeStringDecoder : (String -> Maybe v) -> Decoder (Maybe v)
maybeStringDecoder parser =
  Json.Decode.map parser string

setDecoder : Decoder (Set.Set String)
setDecoder =
  Json.Decode.map Set.fromList (Json.Decode.list string) 

messagesDecoder : Decoder Bcc.Messages
messagesDecoder =
  Json.Decode.succeed Bcc.Messages
    |> JP.required "commandsHandled" setDecoder
    |> JP.required "commandsSent" setDecoder
    |> JP.required "eventsHandled" setDecoder
    |> JP.required "eventsPublished" setDecoder
    |> JP.required "queriesHandled" setDecoder
    |> JP.required "queriesInvoked" setDecoder
    
modelDecoder : Decoder Bcc.BoundedContextCanvas
modelDecoder =
  Json.Decode.succeed Bcc.BoundedContextCanvas
    |> JP.required "name" string
    |> JP.optional "description" string ""
    |> JP.optional "classification" (maybeStringDecoder Bcc.classificationParser) Nothing 
    |> JP.optional "businessModel" (maybeStringDecoder Bcc.businessModelParser) Nothing
    |> JP.optional "evolution" (maybeStringDecoder Bcc.evolutionParser) Nothing
    |> JP.optional "businessDecisions" string ""
    |> JP.optional "ubiquitousLanguage" string ""
    |> JP.optional "modelTraits" string ""
    |> JP.optional "messages" messagesDecoder (Bcc.initMessages ())

    