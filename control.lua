-- ponytail: example control-stage handler — replace with your own.
-- on_init fires on a fresh save, so the load-smoke / bench exercises this.
script.on_init(function()
  storage.example_init = true
end)
