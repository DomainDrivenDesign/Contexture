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
import Bootstrap.Form.Select as Select
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Form.Radio as Radio
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Button as Button
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Text as Text
import Bootstrap.Utilities.Flex as Flex
import Bootstrap.Utilities.Spacing as Spacing


import Url

import Set
import Dict
import Http

import Route
import Bcc

-- MODEL

type alias EditingCanvas = 
  { canvas : Bcc.BoundedContextCanvas
  , addingMessage : AddingMessage
  , addingDependencies: AddingDependencies
  }
type alias AddingMessage = 
  { commandsHandled : Bcc.Command
  , commandsSent : Bcc.Command
  , eventsHandled : Bcc.Event
  , eventsPublished : Bcc.Event
  , queriesHandled : Bcc.Query
  , queriesInvoked : Bcc.Query
  }

type alias AddingDependency =
  { system: Bcc.System
  , relationship: Maybe Bcc.Relationship }

type alias AddingDependencies =
  { consumer: AddingDependency
  , supplier: AddingDependency
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

initDependency = 
  { system = "", relationship = Nothing } 

initAddingDependencies = 
  { consumer = initDependency
  , supplier = initDependency
  }

init : Nav.Key -> Url.Url -> (Model, Cmd Msg)
init key url =
  let
    model =
      { key = key
      , self = url
      , edit = 
        { addingMessage = initAddingMessage
        , addingDependencies = initAddingDependencies
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
  = CommandsHandled Bcc.Message
  | CommandsSent Bcc.Message
  | EventsHandled Bcc.Message
  | EventsPublished Bcc.Message
  | QueriesHandled Bcc.Message
  | QueriesInvoked Bcc.Message


type DependencyFieldMsg
  = SetSystem Bcc.System
  | SetRelationship String
  -- | ChangeDependency (Bcc.Action Bcc.Dependency)

type DependenciesFieldMsg
  = Consumer DependencyFieldMsg
  | Supplier DependencyFieldMsg


type EditingMsg
  = Field Bcc.Msg
  | MessageField MessageFieldMsg
  | DependencyField DependenciesFieldMsg

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
      { model | commandsHandled = cmd }
    CommandsSent cmd ->
      { model | commandsSent = cmd }
    EventsHandled event ->
      { model | eventsHandled = event }
    EventsPublished event ->
      { model | eventsPublished = event }
    QueriesHandled query ->
      { model | queriesHandled = query }
    QueriesInvoked query ->
      { model | queriesInvoked = query }

updateAddingDependency : DependencyFieldMsg -> AddingDependency -> AddingDependency
updateAddingDependency msg model =
  case msg of
    SetSystem system ->
      { model | system = system }
    SetRelationship relationship ->
      { model | relationship = Bcc.relationshipParser relationship }

updateAddingDependencies : DependenciesFieldMsg -> AddingDependencies -> AddingDependencies
updateAddingDependencies msg model =
  case msg of
    Consumer conMsg ->
      { model | consumer = updateAddingDependency conMsg model.consumer }
    Supplier supMsg ->
      { model | supplier = updateAddingDependency supMsg model.supplier }
      

updateEdit : EditingMsg -> EditingCanvas -> EditingCanvas
updateEdit msg model =
  case msg of
    Field (Bcc.ChangeMessages change) ->
      let
        addingMessageModel = model.addingMessage
        addingMessage = 
          case change of
            Bcc.CommandHandled _ ->
              { addingMessageModel | commandsHandled = "" }
            Bcc.CommandSent _ ->
              { addingMessageModel | commandsSent = "" }
            Bcc.EventsHandled _ ->
              { addingMessageModel | eventsHandled = "" }
            Bcc.EventsPublished _ ->
              { addingMessageModel | eventsPublished = "" }
            Bcc.QueriesHandled _ ->
              { addingMessageModel | queriesHandled = "" }
            Bcc.QueriesInvoked _ ->
              { addingMessageModel | queriesInvoked = "" }
      in
        { model | canvas = Bcc.update (Bcc.ChangeMessages change) model.canvas, addingMessage = addingMessage }
    Field (Bcc.ChangeDependencies change) ->
      let
        addingDependenciesModel = model.addingDependencies
        addingDependencies =
          case change of
            Bcc.Supplier _ ->
              { addingDependenciesModel | supplier = initDependency }
            Bcc.Consumer _ ->
              { addingDependenciesModel | consumer = initDependency }
      in
        { model | canvas = Bcc.update (Bcc.ChangeDependencies change) model.canvas, addingDependencies = addingDependencies }
    Field fieldMsg ->
      { model | canvas = Bcc.update fieldMsg model.canvas }
    DependencyField depMsg ->
      { model | addingDependencies = updateAddingDependencies depMsg model.addingDependencies }
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
        editing = 
          { canvas = m
          , addingMessage = initAddingMessage
          , addingDependencies = initAddingDependencies
          }
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

viewMessageOption : (Bcc.MessageAction   -> Bcc.MessageMsg) -> Bcc.Message -> ListGroup.Item Bcc.MessageMsg
viewMessageOption remove model =
  ListGroup.li 
    [ ListGroup.attrs [ Flex.block, Flex.justifyBetween, Flex.alignItemsCenter, Spacing.p1 ] ] 
    [ text model
    , Button.button [Button.danger, Button.small, Button.onClick (remove (Bcc.Remove model))] [ text "x"]
    ]

type alias MessageEdit =
  { messages: Set.Set Bcc.Message
  , message : Bcc.Message
  , modifyMessageCmd : Bcc.MessageAction -> Bcc.MessageMsg
  , updateNewMessageText : String -> MessageFieldMsg
  }

viewMessage : String -> String -> MessageEdit -> Html EditingMsg
viewMessage id title edit =
  Form.group [Form.attrs [style "min-height" "250px"]]
    [ Form.label [for id] [ text title]
    , ListGroup.ul 
      (
        edit.messages
        |> Set.toList
        |> List.map (viewMessageOption edit.modifyMessageCmd)
      )
      |> Html.map (Bcc.ChangeMessages >> Field)
    , Form.form 
      [ Html.Events.onSubmit 
          (edit.message
            |> Bcc.Add
            |> edit.modifyMessageCmd
            |> Bcc.ChangeMessages
            |> Field
          )
      , Flex.block, Flex.justifyBetween, Flex.alignItemsCenter
      ]
      [ InputGroup.config 
          ( InputGroup.text
            [ Input.id id
            , Input.value edit.message
            , Input.onInput edit.updateNewMessageText 
            ]
          )
          |> InputGroup.successors
            [ InputGroup.button [ Button.attrs [ Html.Attributes.type_ "submit"],  Button.secondary] [ text "Add"] ]
          |> InputGroup.view
          |> Html.map MessageField
      ]
    ] 

viewMessages : EditingCanvas -> Html EditingMsg
viewMessages editing =
  let
    messages = editing.canvas.messages
    addingMessage = editing.addingMessage
  in
  div []
    [ Html.h5 [ class "text-center" ] [ text "Messages Consumed and Produced" ]
    , Grid.row []
      [ Grid.col [] 
        [ Html.h6 [ class "text-center" ] [ text "Messages consumed"]
        , { messages = messages.commandsHandled
          , message = addingMessage.commandsHandled
          , modifyMessageCmd = Bcc.CommandHandled
          , updateNewMessageText = CommandsHandled
          } |> viewMessage "commandsHandled" "Commands handled"
        , { messages = messages.eventsHandled
          , message = addingMessage.eventsHandled
          , modifyMessageCmd = Bcc.EventsHandled
          , updateNewMessageText = EventsHandled
          } |> viewMessage "eventsHandled" "Events handled"
        , { messages = messages.queriesHandled
          , message = addingMessage.queriesHandled
          , modifyMessageCmd = Bcc.QueriesHandled
          , updateNewMessageText = QueriesHandled
          } |> viewMessage "queriesHandled" "Queries handled"
        ]
      , Grid.col []
        [ Html.h6 [ class "text-center" ] [ text "Messages produced"]
        , { messages = messages.commandsSent
          , message = addingMessage.commandsSent
          , modifyMessageCmd = Bcc.CommandSent
          , updateNewMessageText = CommandsSent
          } |> viewMessage "commandsSent" "Commands sent"
        , { messages = messages.eventsPublished
          , message = addingMessage.eventsPublished
          , modifyMessageCmd = Bcc.EventsPublished
          , updateNewMessageText = EventsPublished
          } |> viewMessage "eventsPublished" "Events published"
        , { messages = messages.queriesInvoked
          , message = addingMessage.queriesInvoked
          , modifyMessageCmd = Bcc.QueriesInvoked
          , updateNewMessageText = QueriesInvoked
          } |> viewMessage "queriesInvoked" "Queries invoked"
        ]
      ]
    ]

translateRelationship : Bcc.Relationship -> String
translateRelationship relationship =
  case relationship of
    Bcc.AntiCorruptionLayer -> "Anti Corruption Layer"
    Bcc.OpenHostService -> "Open Host Service"
    Bcc.PublishedLanguage -> "Published Language"
    Bcc.SharedKernel ->"Shared Kernel"
    Bcc.UpstreamDownstream -> "Upstream/Downstream"
    Bcc.Conformist -> "Conformist"
    Bcc.Octopus -> "Octopus"
    Bcc.Partnership -> "Partnership"
    Bcc.CustomerSupplier -> "Customer/Supplier"

viewDepencency : (Bcc.Action Bcc.Dependency -> Bcc.DependenciesMsg) -> Bcc.Dependency -> Html EditingMsg
viewDepencency removeCmd (system, relationship) =
  Grid.row []
    [ Grid.col [] [text system]
    , Grid.col [] [text (Maybe.withDefault "not specified" (relationship |> Maybe.map translateRelationship))]
    , Grid.col [ Col.xs2 ] 
      [ Button.button 
        [ Button.danger
        , Button.onClick (
            (system, relationship)
            |> Bcc.Remove |> removeCmd |> Bcc.ChangeDependencies |> Field
          ) 
        ]
        [ text "x" ]
      ]
    ]

viewAddDependency : (DependencyFieldMsg -> DependenciesFieldMsg) -> (Bcc.Action Bcc.Dependency -> Bcc.DependenciesMsg) -> AddingDependency -> Html EditingMsg
viewAddDependency editCmd addCmd model =
  let
    items =
      [ Bcc.AntiCorruptionLayer
      , Bcc.OpenHostService
      , Bcc.PublishedLanguage
      , Bcc.SharedKernel
      , Bcc.UpstreamDownstream
      , Bcc.Conformist
      , Bcc.Octopus
      , Bcc.Partnership
      , Bcc.CustomerSupplier
      ]
        |> List.map (\r -> (r,translateRelationship r))
        |> List.map (\(v,t) -> Select.item [value (Bcc.relationshipToString v)] [ text t])
  in
  Form.form 
    [ Html.Events.onSubmit
      (
        (model.system, model.relationship)
        |> Bcc.Add >> addCmd >> Bcc.ChangeDependencies >> Field
      ) 
    ] 
    [ Grid.row []
      [ Grid.col [] 
        [ Input.text
          [ Input.value model.system
          , Input.onInput (SetSystem >> editCmd >> DependencyField)
          ]
        ] 
      , Grid.col [] 
        [ Select.select [ Select.onChange (SetRelationship >> editCmd >> DependencyField) ]
            (List.append [ Select.item [ selected (model.relationship == Nothing), value "" ] [text "unknown"] ] items)
        ]
      , Grid.col [ Col.xs2 ]
        [ Button.submitButton [ Button.secondary ] [ text "+" ]
        ]
      ]
    ]
viewDependencies : EditingCanvas -> Html EditingMsg
viewDependencies model =
  div []
    [ Html.h5 [ class "text-center" ] [ text "Dependencies and Relationships" ]
    , Grid.row []
      [ Grid.col []
        [ Html.h6 [ class "text-center" ] [ text "Message Suppliers" ]
        , Grid.row []
          [ Grid.col [] [ Html.h6 [] [ text "Name"] ]
          , Grid.col [] [ Html.h6 [] [ text "Relationship"] ]
          , Grid.col [Col.xs2] []
          ]
        , div [] 
          (model.canvas.dependencies.suppliers
          |> Dict.toList
          |> List.map (viewDepencency Bcc.Supplier))
        , viewAddDependency Supplier  Bcc.Supplier model.addingDependencies.supplier
        ]
      , Grid.col []
        [ Html.h6 [ class "text-center" ] [ text "Message Consumers" ]
        , Grid.row []
          [ Grid.col [] [ Html.h6 [] [ text "Name"] ]
          , Grid.col [] [ Html.h6 [] [ text "Relationship"] ]
          , Grid.col [Col.xs2] []
          ]
        , div [] 
          (model.canvas.dependencies.consumers
          |> Dict.toList
          |> List.map (viewDepencency Bcc.Consumer))
        , viewAddDependency Consumer Bcc.Consumer model.addingDependencies.consumer
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
    , viewDependencies model
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
    , expect = Http.expectJson Loaded Bcc.modelDecoder
    }

saveBCC: Model -> Cmd Msg
saveBCC model =
    Http.request
      { method = "PUT"
      , headers = []
      , url = Url.toString model.self
      , body = Http.jsonBody <| Bcc.modelEncoder model.edit.canvas
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
