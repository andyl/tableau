defmodule Tableau.PageExtension do
  @moduledoc """
  Content files (with YAML frontmatter) in the configured pages directory will be automatically compiled into Tableau pages.

  Certain frontmatter keys are required and all keys are passed as options to the `Tableau.Page`.

  ## Options

  Frontmatter is compiled with `yaml_elixir` and all keys are converted to atoms.

  * `:title` - The title of the page
  * `:permalink` - The permalink of the page.
  * `:layout` - A string representation of a Tableau layout module.

  ## Example

  ```yaml
  id: "GettingStarted"
  title: "Getting Started"
  permalink: "/docs/:title"
  layout: "ElixirTools.PageLayout"
  ```

  ## Permalink

  The permalink is a string with colon prefixed template variables.

  These variables will be swapped with the corresponding YAML Frontmatter key, with the result being piped through `to_string/1`.

  ## Configuration

  - `:enabled` - boolean - Extension is active or not.
  - `:dir` - string - Directory to scan for markdown files. Defaults to `_pages`
  - `:permalink` - string - Default output path for pages. Accepts `:title` as a replacement keyword, replaced with the page's provided title. If a page has a `:permalink` provided, that will override this value _for that page_.
  - `:layout` - string - Elixir module providing page layout for pages. Default is nil.

  ### Example

  ```elixir
  config :tableau, Tableau.PageExtension,
    enabled: true,
    dir: "_docs",
    permalink: "/docs/:title",
    layout: "MyApp.PageLayout"
  ```

  ## Content formats

  If you're interested in authoring your content in something other than markdown (or you want to use a different markdown parser), you can configure
  a converter for your format in the global configuration.

  Currently the `Tableau.MDExConverter` is the only builtin converter, but you are free to write your own!

  ```elixir
  # configs/config.exs
  config :tableau, :config,
    converters: [
      md: Tableau.MDExConverter,
      adoc: MySite.AsciiDocConverter
    ],
  ```
  """

  use Tableau.Extension, key: :pages, type: :pre_build, priority: 100

  import Schematic

  alias Tableau.Extension.Common

  def config(input) do
    unify(
      map(%{
        optional(:enabled, true) => bool(),
        optional(:dir, "_pages") => str(),
        optional(:permalink) => str(),
        optional(:layout) => str()
      }),
      input
    )
  end

  def run(token) do
    %{site: %{config: %{converters: converters}}, extensions: %{pages: %{config: config}}} = token

    exts = Enum.map_join(converters, ",", fn {ext, _} -> to_string(ext) end)

    pages =
      config.dir
      |> Path.join("**/*.{#{exts}}")
      |> Common.paths()
      |> Common.entries(fn %{path: path, ext: ext, front_matter: front_matter, pre_convert_body: pre_convert_body} ->
        renderer = fn assigns -> converters[ext].convert(path, front_matter, pre_convert_body, assigns) end

        {build(path, front_matter, pre_convert_body, config), renderer}
      end)

    graph =
      Tableau.Graph.insert(
        token.graph,
        Enum.map(pages, fn {page, renderer} ->
          %Tableau.Page{parent: page.layout, permalink: page.permalink, template: renderer, opts: page}
        end)
      )

    {:ok,
     token
     |> Map.put(:pages, pages |> Enum.unzip() |> elem(0))
     |> Map.put(:graph, graph)}
  end

  defp build(filename, front_matter, body, pages_config) do
    front_matter
    |> Map.put(:__tableau_page_extension__, true)
    |> Map.put(:body, body)
    |> Map.put(:file, filename)
    |> Map.put(:layout, Module.concat([front_matter.layout || pages_config.layout]))
    |> Common.build_permalink(pages_config)
  end
end
