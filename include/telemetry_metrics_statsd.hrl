%% Metric record — equivalent to Telemetry.Metrics structs in the Elixir library.
%%
%% type             : counter | last_value | sum | summary | distribution
%% name             : metric name as atom list, e.g. [http, request, count]
%% event_name       : telemetry event name, e.g. [http, request]
%% measurement      : atom key or fun/1 or fun/2 extracting value from measurements map
%% tags             : ordered list of tag keys to include
%% tag_values       : fun(Metadata) -> map() — transforms metadata before tag extraction
%% keep             : undefined | fun(Metadata) -> boolean() — filter predicate
%% reporter_options : proplist, supports {sampling_rate, float()} and {report_as, counter}

-record(metric, {
    type             :: tms_metric:type(),
    name             :: [atom()],
    event_name       :: [atom()],
    measurement      :: atom()
                      | fun((map()) -> number())
                      | fun((map(), map()) -> number()),
    tags        = [] :: [atom()],
    tag_values       :: fun((map()) -> map()),
    keep             :: undefined | fun((map()) -> boolean()),
    reporter_options = [] :: list()
}).

%% UDP socket record — used by tms_udp and exposed to tests via get_udp/1.

-record(tms_udp, {
    host   :: inet:ip_address() | {local, string()},
    port   :: inet:port_number(),
    socket :: port()
}).
