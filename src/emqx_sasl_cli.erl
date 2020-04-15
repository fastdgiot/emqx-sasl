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

-module(emqx_sasl_cli).

-include("emqx_sasl.hrl").

%% APIs
-export([ load/0
        , unload/0
        , cli/1
        ]).

load() ->
    emqx_ctl:register_command(sasl, {?MODULE, cli}, []).

unload() ->
    emqx_ctl:unregister_command(sasl).

cli(["scram", "add", Username, Password, Salt]) ->
    cli(["scram", "add", Username, Password, Salt, "4096"]);
cli(["scram", "add", Username, Password, Salt, IterationCount]) ->
    execute_when_enabled("scram", fun() ->
        case emqx_sasl_scram:add(list_to_binary(Username),
                                 list_to_binary(Password),
                                 list_to_binary(Salt),
                                 list_to_integer(IterationCount)) of
            ok ->
                emqx_ctl:print("Authentication information added successfully~n");
            {error, already_existed} ->
                emqx_ctl:print("Authentication information already exists~n")
        end
    end);

cli(["scram", "delete", Username0]) ->
    Username = list_to_binary(Username0),
    execute_when_enabled("scram", fun() ->
        ok = emqx_sasl_scram:delete(Username),
        emqx_ctl:print("Authentication information deleted successfully~n")
    end);

cli(["scram", "update", Username, Password, Salt]) ->
    cli(["scram", "update", Username, Password, Salt, "4096"]); 
cli(["scram", "update", Username, Password, Salt, IterationCount]) ->
    execute_when_enabled("scram", fun() ->
        case emqx_sasl_scram:update(list_to_binary(Username),
                                    list_to_binary(Password),
                                    list_to_binary(Salt),
                                    list_to_integer(IterationCount)) of
            ok ->
                emqx_ctl:print("Authentication information updated successfully~n");
            {error, not_found} ->
                emqx_ctl:print("Authentication information not found~n")
        end
    end);

cli(["scram", "lookup", Username0]) ->
    Username = list_to_binary(Username0),
    execute_when_enabled("scram", fun() ->
        case emqx_sasl_scram:lookup(Username) of
            {ok, #{username := Username,
                   stored_key := StoredKey,
                   server_key := ServerKey,
                   salt := Salt,
                   iteration_count := IterationCount}} ->
                emqx_ctl:print("Username: ~s, Stored Key: ~s, Server Key: ~s, Salt: ~s, Iteration Count: ~p~n",
                                [Username, StoredKey, ServerKey, Salt, IterationCount]);
            {error, not_found} ->
                emqx_ctl:print("Authentication information not found~n")
        end
    end);

cli(_) ->
    emqx_ctl:usage([{"sasl scram add <Username> <Password> <Salt> [<IterationCount>]", "Add SCRAM-SHA-1 authentication information"},
                    {"sasl scram delete <Username>", "Delete SCRAM-SHA-1 authentication information"},
                    {"sasl scram update <Username> <Password> <Salt> [<IterationCount>]", "Update SCRAM-SHA-1 authentication information"},
                    {"sasl scram lookup <Username>", "Check if SCRAM-SHA-1 authentication information exists"}]).

execute_when_enabled(Mechanism, Fun) ->
    Enabled = case Mechanism of
                  "scram" -> emqx_sasl_scram:is_enabled();
                  _ -> false
              end,
    case Enabled of
        true ->
            Fun();
        false ->
            emqx_ctl:print("Please load ~p plugin first.~n", [?APP])
    end.
    