module Main exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Markdown.Parser
import Markdown.Renderer


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }


type Model
    = Loading
    | Success String
    | Failure String


type Msg
    = GotReadme (Result Http.Error String)


init : () -> ( Model, Cmd Msg )
init _ =
    ( Loading
    , Http.get
        { url = "README.md"
        , expect = Http.expectString GotReadme
        }
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        GotReadme (Ok markdown) ->
            ( Success markdown, Cmd.none )

        GotReadme (Err err) ->
            ( Failure (httpErrorToString err), Cmd.none )


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "The request timed out."

        Http.NetworkError ->
            "A network error occurred."

        Http.BadStatus code ->
            "Server responded with status " ++ String.fromInt code ++ "."

        Http.BadBody responseBody ->
            "Unexpected response body: " ++ responseBody


view : Model -> Html Msg
view model =
    Html.div [ Attr.class "page" ]
        [ Html.header [ Attr.class "site-header" ]
            [ Html.h1 [] [ Html.text "dochist" ]
            , Html.p [ Attr.class "tagline" ]
                [ Html.text "Session-based command history and artifact provenance logger, with FAIR compliance reporting." ]
            , Html.nav [ Attr.class "site-nav" ]
                [ Html.a [ Attr.href "https://github.com/motroy/dochist" ] [ Html.text "Source" ]
                , Html.text " \u{00B7} "
                , Html.a [ Attr.href "https://github.com/motroy/dochist/releases" ] [ Html.text "Releases" ]
                , Html.text " \u{00B7} "
                , Html.a [ Attr.href "https://github.com/motroy/dochist-docs/releases" ] [ Html.text "Binaries" ]
                ]
            ]
        , Html.main_ [ Attr.class "content" ] [ body model ]
        ]


body : Model -> Html Msg
body model =
    case model of
        Loading ->
            Html.p [ Attr.class "status" ] [ Html.text "Loading documentation\u{2026}" ]

        Failure message ->
            Html.div [ Attr.class "status error" ]
                [ Html.p [] [ Html.text ("Couldn't load the docs: " ++ message) ]
                , Html.p []
                    [ Html.text "View the "
                    , Html.a [ Attr.href "https://github.com/motroy/dochist#readme" ] [ Html.text "README on GitHub" ]
                    , Html.text " instead."
                    ]
                ]

        Success markdown ->
            case
                markdown
                    |> Markdown.Parser.parse
                    |> Result.mapError deadEndsToString
                    |> Result.andThen (Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer)
            of
                Ok rendered ->
                    Html.div [ Attr.class "markdown-body" ] rendered

                Err errors ->
                    Html.pre [ Attr.class "status error" ] [ Html.text errors ]


deadEndsToString deadEnds =
    deadEnds
        |> List.map Markdown.Parser.deadEndToString
        |> String.join "\n"
