%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 80 -*-
%% ex: ts=4 sw=4 et
%% @author Tyler Cloke <tyler@chef.io>
%% Copyright 2015 Chef Software, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(oc_chef_wm_named_keys).

-include("../../include/oc_chef_wm.hrl").

-mixin([{oc_chef_wm_base, [content_types_accepted/2,
                           content_types_provided/2,
                           finish_request/2,
                           malformed_request/2,
                           ping/2,
                           forbidden/2,
                           is_authorized/2,
                           service_available/2]}]).

%% chef_wm behavior callbacks
-behavior(chef_wm).
-export([auth_info/2,
         init/1,
         init_resource_state/1,
         malformed_request_message/3,
         request_type/0,
         validate_request/3]).

-export([allowed_methods/2,
         delete_resource/2,
         from_json/2,
         to_json/2]).

init(Config) ->
    oc_chef_wm_base:init(?MODULE, Config).

init_resource_state(_Config) ->
    {ok, #key_state{}}.

request_type() ->
    "keys".

allowed_methods(Req, State) ->
    {['GET'], Req, State}.

%% TODO
validate_request('GET', Req, #base_state{} = State) ->
    {Req, State}.

%% Permissions are the same as oc_chef_wm_keys. See that file for details.
%% TODO
auth_info(Req, #base_state{resource_args = TargetType} = State) ->
    {Req, State}.

to_json(Req, #base_state{ chef_db_context = DbContext,
                          resource_state = #key_state{parent_id = Id, full_type = FullType, type = Type} } = State) ->
    ct:pal("wtf ~n~p~n", [FullType]),
    ct:pal("lol ~n~p~n", [Type]),
    Name = chef_wm_util:object_name(FullType, Req),
    Key = chef_db:fetch(#chef_key{id = Id, key_name = Name}, DbContext),
    ct:pal("lalala ~n~p~n", [Key]),
    EJ = chef_key:ejson_from_find(Key),
    ct:pal("yayaya ~n~p~n", [EJ]),
    {chef_json:encode(Key), Req, State}.

%% TODO: needed for PUT
from_json(Req, #base_state{}) ->
    error(not_implemented).

%% TODO: needed for DELETE
delete_resource(Req, #base_state{}) ->
    error(not_implemented).

malformed_request_message(Any, _Req, _state) ->
    error({unexpected_malformed_request_message, Any}).
