%% @doc Datadog StatsD formatter — mirrors TelemetryMetricsStatsd.Formatter.Datadog.
%%
%% Tags are appended as |#key:value,key:value suffix.
%% Empty/missing tag values are included as-is (no dropping).
%% Float measurements are sent as floats (not rounded).
-module(tms_formatter_datadog).
-include("telemetry_metrics_statsd.hrl").

-export([format/3]).

-spec format(tms_metric:t(), number(), [{atom(), term()}]) -> iodata().
format(#metric{} = Metric, Value, Tags) ->
    [format_name(Metric#metric.name),
     $:,
     format_value(Metric, Value),
     format_sampling_rate(Metric#metric.reporter_options),
     format_tags(Tags)].

%% ------------------------------------------------------------------ private

-spec format_name([atom()]) -> iodata().
format_name([Seg]) ->
    [atom_to_binary(Seg, utf8)];
format_name([Seg | Rest]) ->
    [atom_to_binary(Seg, utf8), $. | format_name(Rest)].

-spec format_value(tms_metric:t(), number()) -> iodata().
format_value(#metric{type = counter}, _Value) ->
    <<"1|c">>;
format_value(#metric{type = summary}, Value) ->
    [format_number(Value), <<"|h">>];
format_value(#metric{type = distribution}, Value) ->
    [format_number(Value), <<"|d">>];
format_value(#metric{type = last_value}, Value) ->
    [format_number(Value), <<"|g">>];
format_value(#metric{type = sum}, Value) ->
    [format_number(Value), <<"|c">>].

-spec format_number(number()) -> iodata().
format_number(V) when is_integer(V) -> integer_to_binary(V);
format_number(V) when is_float(V)   -> float_to_binary(V, [short]).

-spec format_tags([{atom(), term()}]) -> iodata().
format_tags([]) ->
    [];
format_tags([{K, V} | Rest]) ->
    [<<"|#">>, format_tag(K, V) | combine_tags(Rest)].

-spec combine_tags([{atom(), term()}]) -> iodata().
combine_tags([]) ->
    [];
combine_tags([{K, V} | Rest]) ->
    [$,, format_tag(K, V) | combine_tags(Rest)].

-spec format_tag(atom(), term()) -> iodata().
format_tag(K, nil) ->
    [atom_to_binary(K, utf8), $:, <<"nil">>];
format_tag(K, V) ->
    [atom_to_binary(K, utf8), $:, safe_to_string(V)].

%% Replicates Elixir's String.Chars protocol dispatch:
%% types that implement it are converted, others become "_unprocessable".
-spec safe_to_string(term()) -> binary().
safe_to_string(V) when is_binary(V)  -> V;
safe_to_string(V) when is_atom(V)    -> atom_to_binary(V, utf8);
safe_to_string(V) when is_integer(V) -> integer_to_binary(V);
safe_to_string(V) when is_float(V)   -> float_to_binary(V, [short]);
safe_to_string(V) when is_list(V)    ->
    try iolist_to_binary(V)
    catch _:_ -> <<"_unprocessable">>
    end;
safe_to_string(_) ->
    <<"_unprocessable">>.

-spec format_sampling_rate(list()) -> iodata().
format_sampling_rate(Opts) ->
    case proplists:get_value(sampling_rate, Opts, 1.0) of
        Rate when Rate > 0.0, Rate < 1.0 ->
            [<<"|@">>, float_to_binary(Rate, [short])];
        _ ->
            []
    end.
