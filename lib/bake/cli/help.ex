defmodule Bake.Cli.Help do
  @menu "help"
  @switches []

  use Bake.Cli.Menu
  require Logger

  def menu do
    """
      set variable value  - Set a global variable
      get variable        - Show a global variable
      clear variable      - Clear a global variable
    """
  end

  def main(args) do
    {_opts, cmd, _} = OptionParser.parse(args, switches: @switches)
    mod = List.first(cmd)
    |> String.capitalize
    |> String.to_atom

    mod = Module.concat(Bake.Cli, mod)
    try do
      help =
      case Kernel.apply(mod, :menu, []) do
        "" -> Bake.Cli.menu
        help -> help
      end
      Bake.Shell.info help
    rescue
      _ ->
        Bake.Shell.info "Module #{cmd} unavailable"
        Bake.Shell.info Bake.Cli.menu
    end

  end
end
