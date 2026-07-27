module Main exposing (main)

import Browser
import Char
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Markdown.Block as Block exposing (Block, HeadingLevel(..))
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
    | Failure String
    | Ready (List Block)


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
            case
                markdown
                    |> Markdown.Parser.parse
                    |> Result.mapError deadEndsToString
            of
                Ok blocks ->
                    ( Ready blocks, Cmd.none )

                Err parseError ->
                    ( Failure parseError, Cmd.none )

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


deadEndsToString deadEnds =
    deadEnds
        |> List.map Markdown.Parser.deadEndToString
        |> String.join "\n"



-- TABLE OF CONTENTS


type alias Heading =
    { level : Int
    , text : String
    , slug : String
    }


extractHeadings : List Block -> List Heading
extractHeadings blocks =
    blocks
        |> List.filterMap
            (\block ->
                case block of
                    Block.Heading level inlines ->
                        let
                            text =
                                Block.extractInlineText inlines
                        in
                        Just
                            { level = Block.headingLevelToInt level
                            , text = text
                            , slug = slugify text
                            }

                    _ ->
                        Nothing
            )
        |> List.filter (\heading -> heading.level >= 2 && heading.level <= 3)


slugify : String -> String
slugify text =
    text
        |> String.toLower
        |> String.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    ' '
            )
        |> String.words
        |> String.join "-"



-- VIEW


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
        , Html.div [ Attr.class "layout" ] (body model)
        ]


body : Model -> List (Html Msg)
body model =
    case model of
        Loading ->
            [ Html.p [ Attr.class "status" ] [ Html.text "Loading documentation\u{2026}" ] ]

        Failure message ->
            [ Html.div [ Attr.class "status error" ]
                [ Html.p [] [ Html.text ("Couldn't load the docs: " ++ message) ]
                , Html.p []
                    [ Html.text "View the "
                    , Html.a [ Attr.href "https://github.com/motroy/dochist#readme" ] [ Html.text "README on GitHub" ]
                    , Html.text " instead."
                    ]
                ]
            ]

        Ready blocks ->
            [ Html.nav [ Attr.class "toc" ] (tocView (extractHeadings blocks))
            , Html.main_ [ Attr.class "content" ] (renderBlocks blocks)
            ]


tocView : List Heading -> List (Html Msg)
tocView items =
    Html.p [ Attr.class "toc-title" ] [ Html.text "Contents" ]
        :: List.map tocItem items


tocItem : Heading -> Html Msg
tocItem heading =
    Html.a
        [ Attr.href ("#" ++ heading.slug)
        , Attr.class ("toc-level-" ++ String.fromInt heading.level)
        ]
        [ Html.text heading.text ]


renderBlocks : List Block -> List (Html Msg)
renderBlocks blocks =
    case Markdown.Renderer.render htmlRenderer blocks of
        Ok rendered ->
            rendered

        Err error ->
            [ Html.pre [ Attr.class "status error" ] [ Html.text error ] ]


htmlRenderer : Markdown.Renderer.Renderer (Html msg)
htmlRenderer =
    { Markdown.Renderer.defaultHtmlRenderer | heading = renderHeading }


renderHeading :
    { level : HeadingLevel, rawText : String, children : List (Html msg) }
    -> Html msg
renderHeading { level, rawText, children } =
    let
        attrs =
            [ Attr.id (slugify rawText) ]
    in
    case level of
        H1 ->
            Html.h1 attrs children

        H2 ->
            Html.h2 attrs children

        H3 ->
            Html.h3 attrs children

        H4 ->
            Html.h4 attrs children

        H5 ->
            Html.h5 attrs children

        H6 ->
            Html.h6 attrs children
