%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_auth_sasl_api).

-include("emqx_sasl.hrl").

-import(minirest, [ return/0
                  , return/1
                  ]).

-rest_api(#{name   => list,
            method => 'GET',
            path   => "/sasl",
            func   => list,
            descr  => "List all authentication information"}).

-rest_api(#{name   => add,
            method => 'POST',
            path   => "/sasl",
            func   => add,
            descr  => "Add authentication information"}).

-rest_api(#{name   => delete,
            method => 'DELETE',
            path   => "/sasl",
            func   => delete,
            descr  => "Delete authentication information"}).

-export([ list/2
        , lookup/2
        , add/2
        , delete/2
        ]).

list(#{mechanism := Mechanism}, _Params) ->
    case http_uri:decode(Mechanism) of
        <<"SCRAM-SHA-1">> ->
            Data = #{Mechanism => mnesia:dirty_all_keys(?SCRAM_AUTH_TAB)},
            return({ok, Data});
        _ ->
            return({error, <<"Unsupported mechanism">>})
    end;

list(_Bindings, _Params) ->
    Data = lists:foldl(fun(Mechanism, Acc) ->
                           case Mechanism of
                               <<"SCRAM-SHA-1">> ->
                                   [#{Mechanism => mnesia:dirty_all_keys(?SCRAM_AUTH_TAB)} | Acc]
                           end
                       end, [], emqx_sasl:supported()),
    return({ok, Data}).

lookup(#{mechanism := Mechanism0,
         username := Username0}, _Params) ->
    Mechanism = http_uri:decode(Mechanism0),
    Username = http_uri:decode(Username0),
    case Mechanism of
        <<"SCRAM-SHA-1">> ->
            case emqx_sasl_scram:lookup(Username) of
                {ok, Data} ->
                    return({ok, Data});
                {error, Reason} ->
                    return({error, Reason})
            end;
        _ ->
            return({error, unsupported_mechanism})
    end;
lookup(_Bindings, _Params) ->
    return({error, missing_required_param}).

add(_Bindings, Params) ->
    case pipeline([fun ensure_required_add_params/1,
                   fun validate_params/1,
                   fun do_add/1], Params) of
        ok ->
            return();
        {error, Reason} ->
            return({error, Reason})
    end.

delete(_Bindings, Params) ->
    case pipeline([fun ensure_required_delete_params/1,
                   fun validate_params/1,
                   fun do_delete/1], Params) of
        ok ->
            return();
        {error, Reason} ->
            return({error, Reason})
    end.

ensure_required_add_params(Params) when is_list(Params) ->
    case proplists:get_value(<<"mechanism">>, Params) of
        undefined ->
            {missing, missing_required_param};
        Mechaism ->
            ensure_required_add_params(Mechaism, Params)
    end.

ensure_required_add_params(<<"SCRAM-SHA-1">>, Params) ->
    Required = [<<"username">>, <<"password">>, <<"salt">>],
    case erlang:map_size(maps:with(Required, maps:from_list(Params))) =:= erlang:length(Required) of
        true -> ok;
        false -> {missing, missing_required_param}
    end;
ensure_required_add_params(_, _) ->
    {error, unsupported_mechanism}.

validate_params(Params) ->
    Mechaism = proplists:get_value(<<"mechanism">>, Params),
    validate_params(Mechaism, Params).

validate_params(<<"SCRAM-SHA-1">>, []) ->
    ok;
validate_params(<<"SCRAM-SHA-1">>, [{<<"username">>, Username} | More]) when is_binary(Username) ->
    validate_params(<<"SCRAM-SHA-1">>, More);
validate_params(<<"SCRAM-SHA-1">>, [{<<"username">>, _} | _]) ->
    {error, invalid_username};
validate_params(<<"SCRAM-SHA-1">>, [{<<"password">>, Password} | More]) when is_binary(Password) ->
    validate_params(<<"SCRAM-SHA-1">>, More);
validate_params(<<"SCRAM-SHA-1">>, [{<<"password">>, _} | _]) ->
    {error, invalid_password};
validate_params(<<"SCRAM-SHA-1">>, [{<<"salt">>, Salt} | More]) when is_binary(Salt) ->
    validate_params(<<"SCRAM-SHA-1">>, More);
validate_params(<<"SCRAM-SHA-1">>, [{<<"salt">>, _} | _]) ->
    {error, invalid_salt};
validate_params(<<"SCRAM-SHA-1">>, [{<<"iteration_count">>, IterationCount} | More]) when is_integer(IterationCount) ->
    validate_params(<<"SCRAM-SHA-1">>, More);
validate_params(<<"SCRAM-SHA-1">>, [{<<"iteration_count">>, _} | _]) ->
    {error, invalid_iteration_count};
validate_params(<<"SCRAM-SHA-1">>, [_ | More]) ->
    validate_params(<<"SCRAM-SHA-1">>, More).

do_add(Params) ->
    Mechaism = proplists:get_value(<<"mechanism">>, Params),
    do_add(Mechaism, Params).

do_add(<<"SCRAM-SHA-1">>, Params) ->
    Username = proplists:get_value(<<"username">>, Params),
    Password = proplists:get_value(<<"password">>, Params),
    Salt = base64:decode(proplists:get_value(<<"salt">>, Params)),
    IterationCount = proplists:get_value(<<"iteration_count">>, Params, 4096),
    emqx_sasl_scram:add(Username, Password, Salt, IterationCount);
do_add(_, _) ->
    {error, unsupported_mechanism}.

ensure_required_delete_params(Params) when is_list(Params) ->
    case proplists:get_value(<<"mechanism">>, Params) of
        undefined ->
            {missing, missing_required_param};
        Mechaism ->
            ensure_required_delete_params(Mechaism, Params)
    end.

ensure_required_delete_params(<<"SCRAM-SHA-1">>, Params) ->
    Required = [<<"username">>],
    case erlang:map_size(maps:with(Required, maps:from_list(Params))) =:= erlang:length(Required) of
        true -> ok;
        false -> {missing, missing_required_param}
    end;
ensure_required_delete_params(_, _) ->
    {error, unsupported_mechanism}.

do_delete(Params) ->
    Mechaism = proplists:get_value(<<"mechanism">>, Params),
    do_delete(Mechaism, Params).

do_delete(<<"SCRAM-SHA-1">>, Params) ->
    Username = proplists:get_value(<<"username">>, Params),
    emqx_sasl_scram:delete(Username);
do_delete(_, _) ->
    {error, unsupported_mechanism}.

pipeline([], _) ->
    ok;
pipeline([Fun | More], Params) ->
    case Fun(Params) of
        ok ->
            pipeline(More, Params);
        {error, Reason} ->
            {error, Reason}
    end.


