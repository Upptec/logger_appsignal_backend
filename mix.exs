defmodule LoggerAppsignalBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_appsignal_backend,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [{:appsignal, "~> 1.4"}]
  end
end
