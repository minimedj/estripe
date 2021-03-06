-module(estripe).

-export([create_customer/1]).
-export([update_customer/2]).
-export([delete_customer/1]).
-export([get_customer/1]).
-export([update_subscription/2]).
-export([cancel_subscription/2]).

-export([last_charge/1]).
-export([issue_refund/2]).

-export([customer_id/1]).
-export([active_card/1]).
-export([subscription/1]).

-record(customer, {obj}).
-record(subscription, {obj}).

-define(HTTP_TIMEOUT, 10000).

authorization() ->
    {ok, SK} = application:get_env(estripe, stripe_key),
    {<<"Authorization">>, <<"Bearer ", SK/binary>>}.

create_customer(Params) ->
    Body = form_urlencode(Params),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers",
        "POST",
        [authorization()],
        Body,
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #customer{obj = jiffy:decode(Json)}}.

update_customer(CustomerId, Params) when is_binary(CustomerId) ->
    Body = form_urlencode(Params),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers/" ++ binary_to_list(CustomerId),
        "POST",
        [authorization()],
        Body,
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #customer{obj = jiffy:decode(Json)}}.

delete_customer(CustomerId) when is_binary(CustomerId) ->
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers/" ++ binary_to_list(CustomerId),
        "DELETE",
        [authorization()],
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #customer{obj = jiffy:decode(Json)}}.

get_customer(CustomerId) when is_binary(CustomerId) ->
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers/" ++ binary_to_list(CustomerId),
        "GET",
        [authorization()],
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #customer{obj = jiffy:decode(Json)}}.

update_subscription(CustomerId, Params) ->
    Body = form_urlencode(Params),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers/" ++ binary_to_list(CustomerId) ++ "/subscription",
        "POST",
        [authorization()],
        Body,
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #subscription{obj = jiffy:decode(Json)}}.

cancel_subscription(CustomerId, Params) ->
    Body = form_urlencode(Params),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/customers/" ++ binary_to_list(CustomerId) ++ "/subscription",
        "DELETE",
        [authorization()],
        Body,
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, #subscription{obj = jiffy:decode(Json)}}.

charges(CustomerId) ->
    charges(CustomerId, 0, []).

charges(CustomerId, Offset, Acc) ->
    Params = binary_to_list(form_urlencode([
        {<<"customer">>, CustomerId},
        {<<"count">>, 100},
        {<<"offset">>, Offset}
    ])),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/charges?" ++ Params,
        "GET",
        [authorization()],
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    Charges = get_json_value([<<"data">>], jiffy:decode(Json)),
    case Charges of
        [] ->
            {ok, Acc};
        Charges ->
            charges(CustomerId, Offset + 100, Acc ++ Charges)
    end.

last_charge(CustomerId) ->
    {ok, Charges} = charges(CustomerId),
    case Charges of
        [] ->
            no_charges;
        Charges ->
            {ok, lists:last(Charges)}
    end.

issue_refund(ChargeId, RefundAmount) ->
    Body = form_urlencode([
        {<<"amount">>, RefundAmount}
    ]),
    Res = lhttpc:request(
        "https://api.stripe.com/v1/charges/" ++ binary_to_list(ChargeId) ++ "/refund",
        "POST",
        [authorization()],
        Body,
        ?HTTP_TIMEOUT
    ),
    {ok, {{200, _}, _, Json}} = Res,
    {ok, jiffy:decode(Json)}.

customer_id(#customer{obj = Obj}) ->
    get_json_value([<<"id">>], Obj).

active_card(#customer{obj = Obj}) ->
    get_json_value([<<"active_card">>], Obj).

subscription(#customer{obj = Obj}) ->
    get_json_value([<<"subscription">>], Obj).

form_urlencode(Proplist) ->
    form_urlencode(Proplist, []).

form_urlencode([], Acc) ->
    list_to_binary(string:join(lists:reverse(Acc), "&"));

form_urlencode([{Key, Value} | R], Acc) when is_binary(Key), is_integer(Value) ->
    form_urlencode([{binary_to_list(Key), integer_to_list(Value)} | R], Acc);

form_urlencode([{Key, Value} | R], Acc) when is_list(Key), is_integer(Value) ->
    form_urlencode([{Key, integer_to_list(Value)} | R], Acc);

form_urlencode([{Key, Value} | R], Acc) when is_binary(Key), is_binary(Value) ->
    form_urlencode([{binary_to_list(Key), binary_to_list(Value)} | R], Acc);

form_urlencode([{Key, Value} | R], Acc) when is_list(Key), is_list(Value) ->
    form_urlencode(R, [esc(Key) ++ "=" ++ esc(Value) | Acc]).

esc(S) -> http_uri:encode(S).

get_json_value(_, undefined) ->
    undefined;
get_json_value([], Obj) ->
    Obj;
get_json_value([Key | Rest], {Obj}) ->
    get_json_value(Rest, proplists:get_value(Key, Obj));
get_json_value([Index | _Rest], []) when is_integer(Index) ->
    undefined;
get_json_value([Index | Rest], Obj) when is_integer(Index), is_list(Obj) ->
    get_json_value(Rest, lists:nth(Index + 1, Obj));
get_json_value([Key | Rest], Obj) when is_list(Obj) ->
    get_json_value(Rest, proplists:get_all_values(Key, Obj)).
