%% Tests for tms_formatter (dispatcher with prefix), mirroring formatter_test.exs.
-module(tms_formatter_tests).
-include_lib("eunit/include/eunit.hrl").

-import(tms_helper, [given_counter/2]).

formats_with_prefix_standard_test() ->
    M = given_counter(<<"http.duration">>, [{tags, [resource, method]}]),
    ?assertEqual(
        <<"api.http.duration.users.GET:1|c">>,
        tms_formatter:format(standard, M, <<"api">>, 1, [{resource, <<"users">>}, {method, <<"GET">>}])
    ).

formats_with_prefix_datadog_test() ->
    M = given_counter(<<"http.duration">>, [{tags, [resource, method]}]),
    ?assertEqual(
        <<"api.http.duration:1|c|#resource:users,method:GET">>,
        tms_formatter:format(datadog, M, <<"api">>, 1, [{resource, <<"users">>}, {method, <<"GET">>}])
    ).

formats_with_atom_prefix_datadog_test() ->
    M = given_counter(<<"http.duration">>, [{tags, [resource, method]}]),
    ?assertEqual(
        <<"api.http.duration:1|c|#resource:users,method:GET">>,
        tms_formatter:format(datadog, M, api, 1, [{resource, <<"users">>}, {method, <<"GET">>}])
    ).

formats_without_prefix_standard_test() ->
    M = given_counter(<<"http.duration">>, [{tags, [resource, method]}]),
    ?assertEqual(
        <<"http.duration.users.GET:1|c">>,
        tms_formatter:format(standard, M, undefined, 1, [{resource, <<"users">>}, {method, <<"GET">>}])
    ).

formats_without_prefix_datadog_test() ->
    M = given_counter(<<"http.duration">>, [{tags, [resource, method]}]),
    ?assertEqual(
        <<"http.duration:1|c|#resource:users,method:GET">>,
        tms_formatter:format(datadog, M, undefined, 1, [{resource, <<"users">>}, {method, <<"GET">>}])
    ).
