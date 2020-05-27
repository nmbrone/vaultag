defmodule Vaultag.Logger do
  require Logger

  @prefix "[Vaultag] "

  def debug(msg), do: Logger.debug(@prefix <> msg)
  def info(msg), do: Logger.info(@prefix <> msg)
  def warn(msg), do: Logger.warn(@prefix <> msg)
  def error(msg), do: Logger.error(@prefix <> msg)
end
