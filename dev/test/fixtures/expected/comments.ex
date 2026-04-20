defmodule Comments do
  def run do
    matches1 = Atree.match(tree, %{"value" => 100})   # int64
    matches2 = Atree.match(tree, %{"value" => 100.5}) # double
    matches3 = Atree.match(tree, %{"value" => 25})    # int64
    # This is a very long comment that doesn't fit on one line
    matches4 = Atree.match(tree, %{"value" => 60})
  end
end