%% @doc Standard StatsD formatter — mirrors TelemetryMetricsStatsd.Formatter.Standard.
%%
%% Tags are appended as dot-separated segments of the metric name.
%% Empty string tag values cause the entire metric to be dropped (returns []).
%% All measurements are rounded to integers.
-module(tms_formatter_standard).
-include("telemetry_metrics_statsd.hrl").

-define(LOG_LEVEL_WARNING, warning).

-export([format/3]).

%% Tags: [{atom(), term()}] in the order declared in metric.tags.
-spec format(tms_metric:t(), number(), [{atom(), term()}]) -> iodata().
format(#metric{} = Metric, Value, Tags) ->
    case format_tags(Tags) of
        drop ->
            [];
        FormattedTags ->
            case format_value(Metric, Value) of
                drop ->
                    [];
                FormattedValue ->
                    [format_name(Metric#metric.name),
                     FormattedTags,
                     $:,
                     FormattedValue,
                     format_sampling_rate(Metric#metric.reporter_options)]
            end
    end.

%% ------------------------------------------------------------------ private

-spec format_name([atom()]) -> iodata().
format_name([Seg]) ->
    [atom_to_binary(Seg, utf8)];
format_name([Seg | Rest]) ->
    [atom_to_binary(Seg, utf8), $. | format_name(Rest)].

%% Returns iodata (possibly empty list []) or the atom 'drop'.
-spec format_tags([{atom(), term()}]) -> iodata() | drop.
format_tags([]) ->
    [];
format_tags([{_, <<>>} | _]) ->
    drop;
format_tags([{_, ""} | _]) ->
    drop;
format_tags([{_, nil} | Rest]) ->
    %% nil atom -> literal "nil" string (mirrors Elixir nil handling)
    case format_tags(Rest) of
        drop -> drop;
        Tail -> [$., <<"nil">> | Tail]
    end;
format_tags([{_, V} | Rest]) ->
    case format_tags(Rest) of
        drop -> drop;
        Tail -> [$., tag_value_to_string(V) | Tail]
    end.

-spec tag_value_to_string(term()) -> iodata().
tag_value_to_string(V) when is_binary(V)  -> V;
tag_value_to_string(V) when is_atom(V)    -> atom_to_binary(V, utf8);
tag_value_to_string(V) when is_integer(V) -> integer_to_binary(V);
tag_value_to_string(V) when is_float(V)   -> float_to_binary(V, [short]);
tag_value_to_string(V) when is_list(V)    -> iolist_to_binary(V).

-spec format_value(tms_metric:t(), number()) -> iodata() | drop.
format_value(#metric{type = counter}, _Value) ->
    <<"1|c">>;
format_value(#metric{type = summary}, Value) ->
    [integer_to_binary(round(Value)), <<"|ms">>];
format_value(#metric{type = distribution}, Value) ->
    [integer_to_binary(round(Value)), <<"|ms">>];
format_value(#metric{type = last_value}, Value) ->
    [integer_to_binary(round(Value)), <<"|g">>];
format_value(#metric{type = sum, reporter_options = Opts}, Value) ->
    case proplists:get_value(report_as, Opts) of
        counter when Value >= 0 ->
            [integer_to_binary(round(Value)), <<"|c">>];
        counter ->
            logger:log(?LOG_LEVEL_WARNING,
                "Unable to format negative value: ~p for reporting to StatsD Counter",
                [Value]),
            drop;
        _ when Value >= 0 ->
            [$+, integer_to_binary(round(Value)), <<"|g">>];
        _ ->
            [integer_to_binary(round(Value)), <<"|g">>]
    end.

-spec format_sampling_rate(list()) -> iodata().
format_sampling_rate(Opts) ->
    case proplists:get_value(sampling_rate, Opts, 1.0) of
        Rate when Rate > 0.0, Rate < 1.0 ->
            [<<"|@">>, float_to_binary(Rate, [short])];
        _ ->
            []
    end.
