defmodule Bake.Cli.System do
  use Bake.Cli.Menu

  alias Bake.Utils
  require Logger

  @switches [target: :string, all: :boolean, file: :string]

  defp menu do
    """
      get       - Get a compiled system tar from bakeware.
      clean     - Remove a local system from disk
    """
  end

  def main(args) do
    Bake.start
    {opts, cmd, _} = OptionParser.parse(args, switches: @switches)

    case cmd do
      ["get"] -> get(opts)
      ["clean"] -> clean(opts)
      _ -> invalid_cmd(cmd)
    end
  end

  defp get(opts) do
    {bakefile_path, target_config, target} = bakefile(opts[:bakefile], opts[:target])
    platform = target_config[:platform]
    adapter = adapter(platform)

    lock_path = bakefile_path
    |> Path.dirname
    lock_path = lock_path <> "/Bakefile.lock"

    Enum.each(target_config[:target], fn({target, v}) ->
      Bake.Shell.info "=> Checking system for target #{target}"
      if File.exists?(lock_path) do
        # The exists. Check to see if it contains a lock for our target
        lock_file = Bake.Config.Lock.read(lock_path)
        lock_targets = lock_file[:targets]
        case Keyword.get(lock_targets, target) do
          nil ->
            # Target is not locked, download latest version
            Bake.Api.System.get(%{recipe: v[:recipe]})
            |> get_resp(platform: platform, adapter: adapter, lock_file: lock_path, target: target)
          [{recipe, version}] ->
            system_path = "#{adapter.systems_path}/#{recipe}-#{version}"
            if File.dir?(system_path) do
              Bake.Shell.info "=> System #{recipe} at #{version} up to date"
            else
              Bake.Api.System.get(%{recipe: recipe, version: version})
              |> get_resp(platform: platform, adapter: adapter, lock_file: lock_path, target: target)
            end
        end
      else
        # The lockfile doesn't exist. Download latest version
        Bake.Api.System.get(%{recipe: v[:recipe]})
        |> get_resp(platform: platform, adapter: adapter, lock_file: lock_path, target: target)
      end
    end)
  end

  defp get_resp({:ok, %{status_code: code, body: body}}, opts) when code in 200..299 do
    %{data: %{path: path, host: host, name: name, version: version, username: username}} = Poison.decode!(body, keys: :atoms)

    adapter = opts[:adapter]
    lock_file = opts[:lock_file]
    target = opts[:target]
    Bake.Shell.info "=> Downloading system #{username}/#{name}-#{version}"
    case Bake.Api.request(:get, host <> "/" <> path, []) do
      {:ok, %{status_code: code, body: tar}} when code in 200..299 ->
        Bake.Shell.info "=> System #{username}/#{name}-#{version} downloaded"
        dir = adapter.systems_path <> "/#{username}"
        File.mkdir_p(dir)
        File.write!("#{dir}/#{name}-#{version}.tar.gz", tar)
        Bake.Shell.info "=> Unpacking system #{username}/#{name}-#{version}"
        System.cmd("tar", ["zxf", "#{name}-#{version}.tar.gz"], cd: dir)
        File.rm!("#{dir}/#{name}-#{version}.tar.gz")
        Bake.Config.Lock.write(lock_file, [targets: [{target, ["#{username}/#{name}": version]}]])
      {_, response} ->
        Bake.Shell.error("Failed to download system")
        Bake.Utils.print_response_result(response)
    end
  end

  defp get_resp({_, response}, _platform) do
    Bake.Shell.error("Failed to download system")
    Bake.Utils.print_response_result(response)
  end

  def clean(opts) do
    {bakefile_path, target_config, target} = bakefile(opts[:bakefile], opts[:target])
    platform = target_config[:platform]
    adapter = adapter(platform)

    lock_path = bakefile_path
    |> Path.dirname
    lock_path = lock_path <> "/Bakefile.lock"

    Enum.each(target_config[:target], fn({target, v}) ->
      Bake.Shell.info "=> Cleaning system for target #{target}"
      system_path = adapter.systems_path <> "/#{v[:recipe]}"
      if File.dir?(system_path) do
        Bake.Shell.info "=>    Removing system #{v[:recipe]}"
        File.rm_rf!(system_path)
      else
        Bake.Shell.info "System #{v[:recipe]} not downloaded"
      end
    end)
    Bake.Shell.info "=> Finished"
  end

end
