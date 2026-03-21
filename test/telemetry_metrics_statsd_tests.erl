-module(telemetry_metrics_statsd_tests).
-include_lib("eunit/include/eunit.hrl").
-include("../include/telemetry_metrics_statsd.hrl").

%% exported for supervisor callback used in metrics_not_sent_after_supervisor_shutdown_test
-export([init/1]).

-import(tms_helper, [
    given_udp_port_opened/0, given_udp_port_opened/1,
    given_unix_socket_opened/0,
    start_reporter/1,
    stop_reporter/1,
    assert_reported/2,
    refute_reported/1,
    given_counter/1, given_counter/2,
    given_sum/1, given_sum/2,
    given_last_value/1, given_last_value/2,
    given_summary/1, given_summary/2,
    given_distribution/1, given_distribution/2,
    eventually/1
]).

counter_reported_as_statsd_counter_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>, [{event_name, <<"http.request">>}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}]),
    telemetry:execute([http, request], #{latency => 211}),
    telemetry:execute([http, request], #{latency => 200}),
    telemetry:execute([http, request], #{latency => 198}),
    assert_reported(Socket, <<"http.requests:1|c">>),
    assert_reported(Socket, <<"http.requests:1|c">>),
    assert_reported(Socket, <<"http.requests:1|c">>),
    stop_reporter(Reporter).

sum_reported_as_statsd_gauge_with_plus_n_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Sum = given_sum(<<"http.request.payload_size">>),
    Reporter = start_reporter([{metrics, [Sum]}, {port, Port}]),
    telemetry:execute([http, request], #{payload_size => 2001}),
    telemetry:execute([http, request], #{payload_size => 1585}),
    telemetry:execute([http, request], #{payload_size => 1872}),
    assert_reported(Socket, <<"http.request.payload_size:+2001|g">>),
    assert_reported(Socket, <<"http.request.payload_size:+1585|g">>),
    assert_reported(Socket, <<"http.request.payload_size:+1872|g">>),
    stop_reporter(Reporter).

last_value_reported_as_statsd_gauge_test() ->
    {Socket, Port} = given_udp_port_opened(),
    LV = given_last_value(<<"vm.memory.total">>),
    Reporter = start_reporter([{metrics, [LV]}, {port, Port}]),
    telemetry:execute([vm, memory], #{total => 2001}),
    telemetry:execute([vm, memory], #{total => 1585}),
    telemetry:execute([vm, memory], #{total => 1872}),
    assert_reported(Socket, <<"vm.memory.total:2001|g">>),
    assert_reported(Socket, <<"vm.memory.total:1585|g">>),
    assert_reported(Socket, <<"vm.memory.total:1872|g">>),
    stop_reporter(Reporter).

summary_reported_as_statsd_timer_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Summary = given_summary(<<"http.request.latency">>),
    Reporter = start_reporter([{metrics, [Summary]}, {port, Port}]),
    telemetry:execute([http, request], #{latency => 172}),
    telemetry:execute([http, request], #{latency => 200}),
    telemetry:execute([http, request], #{latency => 198}),
    assert_reported(Socket, <<"http.request.latency:172|ms">>),
    assert_reported(Socket, <<"http.request.latency:200|ms">>),
    assert_reported(Socket, <<"http.request.latency:198|ms">>),
    stop_reporter(Reporter).

distribution_reported_as_statsd_timer_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Dist = given_distribution(<<"http.request.latency">>),
    Reporter = start_reporter([{metrics, [Dist]}, {port, Port}]),
    telemetry:execute([http, request], #{latency => 172}),
    telemetry:execute([http, request], #{latency => 200}),
    telemetry:execute([http, request], #{latency => 198}),
    assert_reported(Socket, <<"http.request.latency:172|ms">>),
    assert_reported(Socket, <<"http.request.latency:200|ms">>),
    assert_reported(Socket, <<"http.request.latency:198|ms">>),
    stop_reporter(Reporter).

standard_formatter_explicit_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {tags, [env, method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port},
                    {formatter, standard}, {global_tags, [{env, <<"prod">>}]}]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200}),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200}),
    assert_reported(Socket, <<"http.requests.prod.GET.200:1|c">>),
    assert_reported(Socket, <<"http.requests.prod.GET.200:1|c">>),
    stop_reporter(Reporter).

datadog_formatter_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {tags, [env, method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port},
                    {formatter, datadog}, {global_tags, [{env, <<"prod">>}]}]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200}),
    telemetry:execute([http, request], #{latency => 200},
                      #{method => <<"POST">>, status => 201}),
    telemetry:execute([http, request], #{latency => 198},
                      #{method => <<"GET">>, status => 404}),
    telemetry:execute([http, request], #{latency => 198},
                      #{method => <<"GET">>, status => 404}),
    assert_reported(Socket, <<"http.requests:1|c|#env:prod,method:GET,status:200">>),
    assert_reported(Socket, <<"http.requests:1|c|#env:prod,method:POST,status:201">>),
    assert_reported(Socket, <<"http.requests:1|c|#env:prod,method:GET,status:404">>),
    assert_reported(Socket, <<"http.requests:1|c|#env:prod,method:GET,status:404">>),
    stop_reporter(Reporter).

invalid_formatter_fails_to_start_test() ->
    Counter = given_counter(<<"http.request.count">>),
    {error, Msg} = telemetry_metrics_statsd:start_link(
        [{metrics, [Counter]}, {formatter, my_formatter}]),
    ?assertEqual(
        "invalid value for :formatter option: expected :formatter be either"
        " :standard or :datadog, got :my_formatter",
        lists:flatten(Msg)).

missing_tag_with_standard_formatter_drops_metric_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.request.count">>, [{tags, [method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}]),
    HandlersBefore = telemetry:list_handlers([]),
    telemetry:execute([http, request], #{latency => 172}, #{method => <<"GET">>}),
    assert_reported(Socket, <<>>),
    HandlersAfter = telemetry:list_handlers([]),
    ?assertEqual(HandlersAfter, HandlersBefore),
    stop_reporter(Reporter).

nil_tag_with_standard_formatter_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.request.count">>, [{tags, [method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}]),
    HandlersBefore = telemetry:list_handlers([]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => nil}),
    assert_reported(Socket, <<"http.request.count.GET.nil:1|c">>),
    HandlersAfter = telemetry:list_handlers([]),
    ?assertEqual(HandlersAfter, HandlersBefore),
    stop_reporter(Reporter).

missing_tag_with_datadog_formatter_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.request.count">>, [{tags, [method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}, {formatter, datadog}]),
    HandlersBefore = telemetry:list_handlers([]),
    telemetry:execute([http, request], #{latency => 172}, #{method => <<"GET">>}),
    assert_reported(Socket, <<"http.request.count:1|c|#method:GET,status:">>),
    HandlersAfter = telemetry:list_handlers([]),
    ?assertEqual(HandlersAfter, HandlersBefore),
    stop_reporter(Reporter).

measurement_function_1_arity_test() ->
    {Socket, Port} = given_udp_port_opened(),
    LV = given_last_value(<<"vm.memory.total">>,
                          [{measurement, fun(M) -> maps:get(total, M) * 2 end}]),
    Reporter = start_reporter([{metrics, [LV]}, {port, Port}]),
    telemetry:execute([vm, memory], #{total => 2001}),
    telemetry:execute([vm, memory], #{total => 1585}),
    telemetry:execute([vm, memory], #{total => 1872}),
    assert_reported(Socket, <<"vm.memory.total:4002|g">>),
    assert_reported(Socket, <<"vm.memory.total:3170|g">>),
    assert_reported(Socket, <<"vm.memory.total:3744|g">>),
    stop_reporter(Reporter).

measurement_function_2_arity_test() ->
    {Socket, Port} = given_udp_port_opened(),
    LV = given_last_value(<<"my.statistics.mean">>,
                          [{measurement,
                            fun(Meas, Meta) ->
                                maps:get(sum, Meas) / maps:get(sample_size, Meta)
                            end}]),
    Reporter = start_reporter([{metrics, [LV]}, {port, Port}]),
    telemetry:execute([my, statistics], #{sum => 200}, #{sample_size => 2}),
    telemetry:execute([my, statistics], #{sum => 300}, #{sample_size => 3}),
    telemetry:execute([my, statistics], #{sum => 100}, #{sample_size => 1}),
    assert_reported(Socket, <<"my.statistics.mean:100|g">>),
    assert_reported(Socket, <<"my.statistics.mean:100|g">>),
    assert_reported(Socket, <<"my.statistics.mean:100|g">>),
    stop_reporter(Reporter).

multiple_metrics_from_same_event_batched_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Dist = given_distribution(<<"http.request.latency">>),
    Sum  = given_sum(<<"http.request.payload_size">>),
    Reporter = start_reporter([{metrics, [Dist, Sum]}, {port, Port}]),
    telemetry:execute([http, request], #{latency => 172, payload_size => 121}),
    telemetry:execute([http, request], #{latency => 200, payload_size => 64}),
    telemetry:execute([http, request], #{latency => 198, payload_size => 1021}),
    assert_reported(Socket,
        <<"http.request.latency:172|ms\nhttp.request.payload_size:+121|g">>),
    assert_reported(Socket,
        <<"http.request.latency:200|ms\nhttp.request.payload_size:+64|g">>),
    assert_reported(Socket,
        <<"http.request.latency:198|ms\nhttp.request.payload_size:+1021|g">>),
    stop_reporter(Reporter).

oversized_payload_split_into_multiple_datagrams_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Metrics = [
        given_counter(<<"first.counter">>,  [{event_name, <<"http.request">>}]),
        given_counter(<<"second.counter">>, [{event_name, <<"http.request">>}]),
        given_counter(<<"third.counter">>,  [{event_name, <<"http.request">>}]),
        given_counter(<<"fourth.counter">>, [{event_name, <<"http.request">>}])
    ],
    Reporter = start_reporter([{metrics, Metrics}, {port, Port}, {mtu, 40}]),
    telemetry:execute([http, request], #{latency => 172, payload_size => 121}),
    assert_reported(Socket, <<"first.counter:1|c\nsecond.counter:1|c">>),
    assert_reported(Socket, <<"third.counter:1|c\nfourth.counter:1|c">>),
    stop_reporter(Reporter).

global_tags_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {tags, [env, host, method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port},
                    {formatter, standard},
                    {global_tags, [{env, <<"dev">>}, {host, <<"localhost">>}]}]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200}),
    assert_reported(Socket, <<"http.requests.dev.localhost.GET.200:1|c">>),
    stop_reporter(Reporter).

event_metadata_overrides_global_tags_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {tags, [env, host, method, status]}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port},
                    {formatter, standard},
                    {global_tags, [{env, <<"dev">>}, {host, <<"localhost">>}]}]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200, host => <<"example.com">>}),
    assert_reported(Socket, <<"http.requests.dev.example.com.GET.200:1|c">>),
    stop_reporter(Reporter).

tag_values_fn_overrides_global_tags_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {tags, [env, host, method, status]},
                             {tag_values, fun(Meta) -> Meta#{host => <<"example.com">>} end}]),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port},
                    {formatter, standard},
                    {global_tags, [{env, <<"dev">>}, {host, <<"localhost">>}]}]),
    telemetry:execute([http, request], #{latency => 172},
                      #{method => <<"GET">>, status => 200}),
    assert_reported(Socket, <<"http.requests.dev.example.com.GET.200:1|c">>),
    stop_reporter(Reporter).

udp_error_logs_and_reopens_socket_test() ->
    Reporter = start_reporter([{metrics, []}, {pool_size, 1}]),
    PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
    {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
    telemetry_metrics_statsd:udp_error(Reporter, Udp, closed),
    eventually(fun() ->
        {ok, NewUdp} = telemetry_metrics_statsd:get_udp(PoolId),
        NewUdp =/= Udp
    end),
    stop_reporter(Reporter).

udp_error_duplicate_ignored_test() ->
    Reporter = start_reporter([{metrics, []}, {pool_size, 1}]),
    PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
    {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
    telemetry_metrics_statsd:udp_error(Reporter, Udp, closed),
    eventually(fun() ->
        {ok, NewUdp} = telemetry_metrics_statsd:get_udp(PoolId),
        NewUdp =/= Udp
    end),
    %% Second report for the same (now-replaced) socket must be silently ignored.
    telemetry_metrics_statsd:udp_error(Reporter, Udp, closed),
    eventually(fun() ->
        {ok, NewUdp} = telemetry_metrics_statsd:get_udp(PoolId),
        NewUdp =/= Udp
    end),
    stop_reporter(Reporter).

udp_error_closes_old_socket_test() ->
    Reporter = start_reporter([{metrics, []}, {pool_size, 1}]),
    PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
    {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
    telemetry_metrics_statsd:udp_error(Reporter, Udp, closed),
    eventually(fun() ->
        {ok, NewUdp} = telemetry_metrics_statsd:get_udp(PoolId),
        NewUdp =/= Udp
    end),
    ?assertEqual({error, closed}, gen_udp:recv(Udp#tms_udp.socket, 0, 100)),
    stop_reporter(Reporter).

unix_domain_socket_test() ->
    {Socket, SocketPath} = given_unix_socket_opened(),
    Counter = given_counter(<<"http.request.count">>),
    Reporter = start_reporter([{metrics, [Counter]}, {socket_path, SocketPath}]),
    telemetry:execute([http, request], #{latency => 213}),
    assert_reported(Socket, <<"http.request.count:1|c">>),
    stop_reporter(Reporter).

prefix_prepended_to_all_metrics_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Metrics = [
        given_counter(<<"http.request.count">>),
        given_distribution(<<"http.request.latency">>),
        given_last_value(<<"http.request.current_memory">>),
        given_sum(<<"http.request.payload_size">>)
    ],
    Reporter = start_reporter([{metrics, Metrics}, {port, Port}, {prefix, <<"myapp">>}]),
    telemetry:execute([http, request],
                      #{latency => 200, current_memory => 200, payload_size => 200}),
    assert_reported(Socket,
        <<"myapp.http.request.count:1|c\n"
          "myapp.http.request.latency:200|ms\n"
          "myapp.http.request.current_memory:200|g\n"
          "myapp.http.request.payload_size:+200|g">>),
    stop_reporter(Reporter).

metrics_not_sent_after_exit_signal_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Reporter = start_reporter([
        {metrics, [given_counter(<<"first.event.count">>),
                   given_counter(<<"second.event.count">>)]},
        {port, Port}
    ]),
    unlink(Reporter),
    %% Exit signal is sent from a separate process (not the test process itself).
    spawn(fun() -> exit(Reporter, some_reason) end),
    eventually(fun() -> not erlang:is_process_alive(Reporter) end),
    ?assertEqual([], telemetry:list_handlers([first, event])),
    ?assertEqual([], telemetry:list_handlers([second, event])),
    telemetry:execute([first, event], #{}),
    telemetry:execute([second, event], #{}),
    refute_reported(Socket).

metrics_not_sent_after_supervisor_shutdown_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Metrics = [given_counter(<<"first.event.count">>),
               given_counter(<<"second.event.count">>)],
    {ok, Sup} = supervisor:start_link(
        {local, ?MODULE},
        ?MODULE, [{metrics, Metrics}, {port, Port}]),
    unlink(Sup),
    Ref = erlang:monitor(process, Sup),
    exit(Sup, shutdown),
    receive {'DOWN', Ref, process, Sup, _} -> ok end,
    ?assertEqual([], telemetry:list_handlers([first, event])),
    ?assertEqual([], telemetry:list_handlers([second, event])),
    telemetry:execute([first, event], #{}),
    telemetry:execute([second, event], #{}),
    refute_reported(Socket).

non_number_measurement_prevents_update_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Sum = given_sum(<<"my.metric">>,
                   [{event_name, <<"my.event">>}, {measurement, non_number}]),
    Reporter = start_reporter([{metrics, [Sum]}, {port, Port}]),
    telemetry:execute([my, event], #{non_number => not_a_number}),
    refute_reported(Socket),
    stop_reporter(Reporter).

counter_outside_sample_rate_not_reported_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {reporter_options, [{sampling_rate, 0.1}]}]),
    %% rand:uniform() returns ~0.328 (> 0.1 → outside sample rate)
    rand:seed(exs1024, {1, 2, 2}),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}]),
    telemetry:execute([http, request], #{sample => 42}),
    refute_reported(Socket),
    stop_reporter(Reporter).

sum_outside_sample_rate_not_reported_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Sum = given_sum(<<"http.request.sample">>,
                    [{reporter_options, [{sampling_rate, 0.1}]}]),
    %% rand:uniform() returns ~0.328 (> 0.1 → outside sample rate)
    rand:seed(exs1024, {1, 2, 2}),
    Reporter = start_reporter([{metrics, [Sum]}, {port, Port}]),
    telemetry:execute([http, request], #{sample => 42}),
    refute_reported(Socket),
    stop_reporter(Reporter).

counter_inside_sample_rate_reported_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>,
                            [{event_name, <<"http.request">>},
                             {reporter_options, [{sampling_rate, 0.1}]}]),
    %% rand:uniform() returns ~0.069 (< 0.1 → inside sample rate)
    rand:seed(exs1024, {1, 2, 3}),
    Reporter = start_reporter([{metrics, [Counter]}, {port, Port}]),
    telemetry:execute([http, request], #{sample => 42}),
    assert_reported(Socket, <<"http.requests:1|c|@0.1">>),
    stop_reporter(Reporter).

sum_inside_sample_rate_reported_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Sum = given_sum(<<"http.request.sample">>,
                    [{reporter_options, [{sampling_rate, 0.1}]}]),
    %% rand:uniform() returns ~0.069 (< 0.1 → inside sample rate)
    rand:seed(exs1024, {1, 2, 3}),
    Reporter = start_reporter([{metrics, [Sum]}, {port, Port}]),
    telemetry:execute([http, request], #{sample => 42}),
    assert_reported(Socket, <<"http.request.sample:+42|g|@0.1">>),
    stop_reporter(Reporter).

keep_and_drop_options_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.request.count">>,
                            [{keep, fun(Meta) -> maps:get(keep, Meta, false) =:= true end}]),
    Summary = given_summary(<<"http.request.duration">>,
                            [{drop, fun(Meta) -> maps:get(drop, Meta, false) =:= true end}]),
    Reporter = start_reporter([{metrics, [Counter, Summary]}, {port, Port}]),
    telemetry:execute([http, request], #{duration => 10}, #{keep => true}),
    assert_reported(Socket, <<"http.request.count:1|c\nhttp.request.duration:10|ms">>),
    telemetry:execute([http, request], #{duration => 10}, #{keep => true, drop => true}),
    assert_reported(Socket, <<"http.request.count:1|c">>),
    telemetry:execute([http, request], #{duration => 10}, #{drop => true}),
    refute_reported(Socket),
    stop_reporter(Reporter).

socket_pool_test() ->
    Reporter = start_reporter([{metrics, []}, {pool_size, 4}]),
    PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
    Udps = lists:usort([begin
        {ok, U} = telemetry_metrics_statsd:get_udp(PoolId), U
    end || _ <- lists:seq(1, 50)]),
    ?assertEqual(4, length(Udps)),
    stop_reporter(Reporter).

multiple_reporters_can_be_started_test() ->
    {Socket, Port} = given_udp_port_opened(),
    Counter = given_counter(<<"http.requests">>, [{event_name, <<"http.request">>}]),
    Reporter1 = start_reporter([{metrics, [Counter]}, {port, Port}]),
    Reporter2 = start_reporter([{metrics, [Counter]}, {port, Port}]),
    telemetry:execute([http, request], #{latency => 211}),
    assert_reported(Socket, <<"http.requests:1|c">>),
    assert_reported(Socket, <<"http.requests:1|c">>),
    stop_reporter(Reporter1),
    stop_reporter(Reporter2).

ipv6_end_to_end_test() ->
    case gen_udp:open(0, [inet6, {active, false}, {ip, {0,0,0,0,0,0,0,1}}]) of
        {error, _} ->
            {skip, "IPv6 loopback (::1) not available on this host"};
        {ok, ProbeSocket} ->
            gen_udp:close(ProbeSocket),
            {Socket, Port} = given_udp_port_opened(inet6),
            Counter = given_counter(<<"http.requests">>, [{event_name, <<"http.request">>}]),
            Reporter = start_reporter([{host, "::1"}, {inet_address_family, inet6},
                            {metrics, [Counter]}, {port, Port}]),
            telemetry:execute([http, request], #{latency => 211}),
            assert_reported(Socket, <<"http.requests:1|c">>),
            stop_reporter(Reporter)
    end.

hostname_resolved_on_start_test() ->
    Counter = given_counter(<<"http.request.count">>),
    Reporter = start_reporter([{host, "localhost"}, {metrics, [Counter]}]),
    PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
    {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
    ?assertEqual({127, 0, 0, 1}, Udp#tms_udp.host),
    stop_reporter(Reporter).

hostname_ipv6_resolution_test() ->
    case gen_udp:open(0, [inet6, {active, false}, {ip, {0,0,0,0,0,0,0,1}}]) of
        {error, _} ->
            {skip, "IPv6 loopback (::1) not available on this host"};
        {ok, ProbeSocket} ->
            gen_udp:close(ProbeSocket),
            Counter = given_counter(<<"http.request.count">>),
            Reporter = start_reporter([{host, "::1"}, {inet_address_family, inet6},
                                       {metrics, [Counter]}]),
            PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
            {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
            ?assertEqual({0,0,0,0,0,0,0,1}, Udp#tms_udp.host),
            stop_reporter(Reporter)
    end.

hostname_not_periodically_resolved_by_default_test() ->
    meck:new(inet, [passthrough, unstick]),
    try
        Counter = given_counter(<<"http.request.count">>),
        Reporter = start_reporter([{host, "localhost"}, {metrics, [Counter]}]),
        PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
        {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
        ?assertEqual({127, 0, 0, 1}, Udp#tms_udp.host),
        meck:expect(inet, gethostbyname, fun(_, _) ->
            {ok, {hostent, "localhost", [], inet, 4, [{10, 0, 0, 0}]}}
        end),
        %% Without host_resolution_interval, no resolve_host message is ever sent,
        %% so DNS is never queried again and the address stays the same.
        timer:sleep(300),
        {ok, Udp2} = telemetry_metrics_statsd:get_udp(PoolId),
        ?assertEqual({127, 0, 0, 1}, Udp2#tms_udp.host),
        meck:unload(inet),
        stop_reporter(Reporter)
    catch C:E:ST ->
        meck:unload(inet),
        erlang:raise(C, E, ST)
    end.

hostname_periodically_resolved_when_configured_test() ->
    meck:new(inet, [passthrough, unstick]),
    try
        Counter = given_counter(<<"http.request.count">>),
        Reporter = start_reporter([{host, "localhost"}, {metrics, [Counter]},
                                   {host_resolution_interval, 100}]),
        PoolId = telemetry_metrics_statsd:get_pool_id(Reporter),
        {ok, Udp} = telemetry_metrics_statsd:get_udp(PoolId),
        ?assertEqual({127, 0, 0, 1}, Udp#tms_udp.host),

        meck:expect(inet, gethostbyname, fun(_, _) ->
            {ok, {hostent, "localhost", [], inet, 4, [{10, 0, 0, 0}]}}
        end),

        eventually(fun() ->
            {ok, U} = telemetry_metrics_statsd:get_udp(PoolId),
            U#tms_udp.host =:= {10, 0, 0, 0}
        end),

        meck:unload(inet),

        eventually(fun() ->
            {ok, U} = telemetry_metrics_statsd:get_udp(PoolId),
            U#tms_udp.host =:= {127, 0, 0, 1}
        end),

        stop_reporter(Reporter)
    catch C:E:ST ->
        meck:unload(inet),
        erlang:raise(C, E, ST)
    end.

%% Supervisor callback for metrics_not_sent_after_supervisor_shutdown_test
init(ReporterOpts) ->
    ChildSpec = #{
        id      => telemetry_metrics_statsd,
        start   => {telemetry_metrics_statsd, start_link, [ReporterOpts]},
        restart => permanent,
        type    => worker
    },
    {ok, {{one_for_one, 5, 10}, [ChildSpec]}}.
