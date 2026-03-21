-module(tms_formatter_standard_tests).
-include_lib("eunit/include/eunit.hrl").
-include("../include/telemetry_metrics_statsd.hrl").

-import(tms_helper, [
    given_counter/1, given_counter/2,
    given_sum/1, given_sum/2,
    given_last_value/1, given_last_value/2,
    given_summary/1, given_summary/2,
    given_distribution/1, given_distribution/2
]).

format(Metric, Value, Tags) ->
    iolist_to_binary(tms_formatter_standard:format(Metric, Value, Tags)).

counter_formatted_as_statsd_counter_with_1_test() ->
    M = given_counter(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:1|c">>, format(M, 30, [])).

positive_sum_formatted_as_gauge_with_plus_n_test() ->
    M = given_sum(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:+21|g">>, format(M, 21, [])).

negative_sum_formatted_as_gauge_with_minus_n_test() ->
    M = given_sum(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:-21|g">>, format(M, -21, [])).

positive_sum_as_counter_test() ->
    M = given_sum(<<"my.awesome.metric">>, [{reporter_options, [{report_as, counter}]}]),
    ?assertEqual(<<"my.awesome.metric:21|c">>, format(M, 21, [])).

negative_sum_as_counter_is_dropped_test() ->
    M = given_sum(<<"my.awesome.metric">>, [{reporter_options, [{report_as, counter}]}]),
    ?assertEqual(<<>>, format(M, -21, [])).

last_value_formatted_as_gauge_with_absolute_value_test() ->
    M = given_last_value(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:-18|g">>, format(M, -18, [])).

summary_formatted_as_statsd_timer_test() ->
    M = given_summary(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:121|ms">>, format(M, 121, [])).

distribution_formatted_as_statsd_timer_test() ->
    M = given_distribution(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:131|ms">>, format(M, 131, [])).

metric_name_based_on_name_and_tags_test() ->
    M = given_last_value(<<"my.awesome.metric">>, [{tags, [method, status]}]),
    ?assertEqual(
        <<"my.awesome.metric.GET.200:131|g">>,
        format(M, 131, [{method, <<"GET">>}, {status, 200}])
    ).

nil_tags_included_in_formatted_metric_test() ->
    M = given_last_value(<<"my.awesome.metric">>, [{tags, [method, status]}]),
    ?assertEqual(
        <<"my.awesome.metric.GET.nil:131|g">>,
        format(M, 131, [{method, <<"GET">>}, {status, nil}])
    ).

empty_string_tag_values_are_dropped_test() ->
    M = given_last_value(<<"my.awesome.metric">>, [{tags, [method, status]}]),
    ?assertEqual(<<>>, format(M, 131, [{method, <<"GET">>}, {status, <<>>}])).

tags_passed_as_explicit_argument_used_test() ->
    %% metric.tags = [:whatever] but format receives method/status — all are used
    M = given_last_value(<<"my.awesome.metric">>, [{tags, [whatever]}]),
    ?assertEqual(
        <<"my.awesome.metric.GET.200:131|g">>,
        format(M, 131, [{method, <<"GET">>}, {status, 200}])
    ).

float_measurements_rounded_to_integers_test() ->
    M = given_last_value(<<"my.awesome.metric">>),
    ?assertEqual(<<"my.awesome.metric:131|g">>, format(M, 131.4, [])),
    ?assertEqual(<<"my.awesome.metric:132|g">>, format(M, 131.5, [])).

sampling_rate_added_to_third_field_test() ->
    M = given_last_value(<<"my.awesome.metric">>,
                         [{reporter_options, [{sampling_rate, 0.2}]}]),
    ?assertEqual(<<"my.awesome.metric:131|g|@0.2">>, format(M, 131.4, [])).

sampling_rate_ignored_if_1_0_test() ->
    M = given_last_value(<<"my.awesome.metric">>,
                         [{reporter_options, [{sampling_rate, 1.0}]}]),
    ?assertEqual(<<"my.awesome.metric:131|g">>, format(M, 131.4, [])).
