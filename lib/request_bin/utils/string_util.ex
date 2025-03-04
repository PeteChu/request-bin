defmodule RequestBin.Utils.StringUtil do
  def kebab_case_with_caps(string) do
    string
    # Split the string into words
    |> String.split("-")
    # Capitalize each word
    |> Enum.map(&String.capitalize/1)
    # Join with hyphens for kebab case
    |> Enum.join("-")
  end
end
