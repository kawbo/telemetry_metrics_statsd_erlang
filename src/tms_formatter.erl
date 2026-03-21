%% @doc Formatter dispatcher — mirrors TelemetryMetricsStatsd.Formatter.
%%
%% Applies prefix (if any), delegates to the correct formatter module,
%% and returns a binary.
-module(tms_formatter).
-include("telemetry_metrics_statsd.hrl").

-export([format/5]).

-type formatter() :: standard | datadog.
-type prefix()    :: binary() | atom() | undefined.

-export_type([formatter/0, prefix/0]).

-spec format(formatter(), tms_metric:t(), prefix(), number(), [{atom(), term()}]) -> binary().
format(Formatter, Metric, undefined, Value, Tags) ->
    iolist_to_binary(do_format(Formatter, Metric, Value, Tags));
format(Formatter, Metric, Prefix, Value, Tags) ->
    iolist_to_binary([prefix_to_binary(Prefix), $., do_format(Formatter, Metric, Value, Tags)]).

-spec do_format(formatter(), tms_metric:t(), number(), [{atom(), term()}]) -> iodata().
do_format(standard, Metric, Value, Tags) ->
    tms_formatter_standard:format(Metric, Value, Tags);
do_format(datadog, Metric, Value, Tags) ->
    tms_formatter_datadog:format(Metric, Value, Tags).

-spec prefix_to_binary(binary() | atom()) -> binary().
prefix_to_binary(P) when is_binary(P) -> P;
prefix_to_binary(P) when is_atom(P)   -> atom_to_binary(P, utf8).
