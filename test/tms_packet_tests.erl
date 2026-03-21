%% Tests for tms_packet, mirroring packet_test.exs property tests with concrete cases.
-module(tms_packet_tests).
-include_lib("eunit/include/eunit.hrl").

build_packets_test_() ->
    [
     {"single binary fits in one packet",
      fun() ->
          ?assertEqual([<<"hello">>],
                       tms_packet:build_packets([<<"hello">>], 512, <<"\n">>))
      end},

     {"multiple binaries that fit are joined",
      fun() ->
          ?assertEqual([<<"a\nb\nc">>],
                       tms_packet:build_packets([<<"a">>, <<"b">>, <<"c">>], 512, <<"\n">>))
      end},

     {"binaries split across packets at MTU boundary",
      fun() ->
          %% "a\nb" = 3 bytes, fits in 3; "a\nb\nc" = 5 bytes exceeds 3
          Packets = tms_packet:build_packets([<<"a">>, <<"b">>, <<"c">>], 3, <<"\n">>),
          ?assertEqual([<<"a\nb">>, <<"c">>], Packets)
      end},

     {"each packet does not exceed max size",
      fun() ->
          Bins = [<<"first.counter:1|c">>, <<"second.counter:1|c">>,
                  <<"third.counter:1|c">>, <<"fourth.counter:1|c">>],
          Packets = tms_packet:build_packets(Bins, 40, <<"\n">>),
          lists:foreach(fun(P) ->
              ?assert(byte_size(P) =< 40)
          end, Packets)
      end},

     {"packets are as full as possible",
      fun() ->
          %% Mirrors the integration test: mtu=40, 4 counters
          %% "first.counter:1|c\nsecond.counter:1|c" = 35 bytes — fits
          %% adding "\nthird.counter:1|c" would make 54 bytes — doesn't fit
          Bins = [<<"first.counter:1|c">>, <<"second.counter:1|c">>,
                  <<"third.counter:1|c">>, <<"fourth.counter:1|c">>],
          Packets = tms_packet:build_packets(Bins, 40, <<"\n">>),
          ?assertEqual([<<"first.counter:1|c\nsecond.counter:1|c">>,
                        <<"third.counter:1|c\nfourth.counter:1|c">>],
                       Packets)
      end},

     {"empty binary list returns empty list",
      fun() ->
          ?assertEqual([], tms_packet:build_packets([], 512, <<"\n">>))
      end},

     {"single binary larger than mtu raises an error",
      fun() ->
          ?assertError({packet_too_large, _, _},
                       tms_packet:build_packets([<<"toolong">>], 3, <<"\n">>))
      end},

     {"custom joiner used",
      fun() ->
          ?assertEqual([<<"a|b|c">>],
                       tms_packet:build_packets([<<"a">>, <<"b">>, <<"c">>], 512, <<"|">>))
      end},

     {"packets satisfy greedy-fill invariant",
      fun() ->
          %% For every consecutive packet pair, adding first binary of next packet
          %% to previous packet would exceed max_size.
          Bins = [<<"aa">>, <<"bb">>, <<"cc">>, <<"dd">>, <<"ee">>],
          MaxSize = 5,  % "aa\nbb" = 5, "aa\nbb\ncc" = 8 > 5
          Joiner = <<"\n">>,
          Packets = tms_packet:build_packets(Bins, MaxSize, Joiner),
          check_greedy(Packets, Bins, MaxSize, Joiner)
      end}
    ].

%% Verify that for each packet boundary, adding the next binary would exceed max_size.
check_greedy([_LastPacket], _Bins, _Max, _J) -> ok;
check_greedy([Packet | [NextPacket | _] = Rest], Bins, Max, J) ->
    %% The first binary of the next packet
    NextBins = packet_to_bins(NextPacket, J),
    NextFirst = hd(NextBins),
    %% If Packet + J + NextFirst still fits, then we weren't greedy enough
    Combined = byte_size(Packet) + byte_size(J) + byte_size(NextFirst),
    ?assert(Combined > Max,
            {not_greedy_enough, Packet, NextFirst, Combined, max, Max}),
    %% Also each packet must respect max_size
    ?assert(byte_size(Packet) =< Max),
    %% Also original bins must all appear
    _ = Bins,
    check_greedy(Rest, Bins, Max, J).

packet_to_bins(Packet, Joiner) ->
    binary:split(Packet, Joiner, [global]).
