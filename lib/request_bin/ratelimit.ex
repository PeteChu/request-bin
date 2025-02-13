defmodule RequestBin.RateLimit do
  use Hammer, backend: :ets
end
