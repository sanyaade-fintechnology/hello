% Copyright (c) 2010-2011 by Travelping GmbH <info@travelping.com>

% Permission is hereby granted, free of charge, to any person obtaining a
% copy of this software and associated documentation files (the "Software"),
% to deal in the Software without restriction, including without limitation
% the rights to use, copy, modify, merge, publish, distribute, sublicense,
% and/or sell copies of the Software, and to permit persons to whom the
% Software is furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
% DEALINGS IN THE SOFTWARE.

% @private
-module(hello_stateless_zmq_server).
-behaviour(gen_server).
-export([start_link/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include_lib("ex_uri/include/ex_uri.hrl").

%% --------------------------------------------------------------------------------
%% -- API
start_link(URI, Module) ->
    gen_server:start_link(?MODULE, {URI, Module}, []).

%% --------------------------------------------------------------------------------
%% -- gen_server callbacks
-record(state, {socket, context, mod}).

init({URI = #ex_uri{}, CallbackModule}) ->
    case hello_registry:register(reg_key(URI), CallbackModule, self()) of
        ok ->
            process_flag(trap_exit, true),
            Endpoint = ex_uri:encode(URI),
            {ok, Context} = erlzmq:context(),
            {ok, Socket} = erlzmq:socket(Context, [rep, {active, true}]),
            case erlzmq:bind(Socket, Endpoint) of
                ok ->
                    {ok, #state{socket = Socket, context = Context, mod = CallbackModule}};
                {error, Error} ->
                    {stop, Error}
            end;
        {already_registered, _Pid, CallbackModule} ->
            {stop, already_started};
        {already_registered, _Pid, _OtherModule} ->
            {stop, occupied}
    end.

handle_info({zmq, Socket, Message, []}, State = #state{socket = Socket, mod = Mod}) ->
    JSONReply = hello:run_stateless_binary_request(Mod, Message),
    ok = erlzmq:send(Socket, JSONReply),
    {noreply, State}.

terminate(_Reason, State) ->
    erlzmq:close(State#state.socket),
    erlzmq:term(State#state.context).

%% unused callbacks
handle_call(_Call, _From, State) ->
    {reply, {error, unknown_call}, State}.
handle_cast(_Cast, State) ->
    {noreply, State}.
code_change(_FromVsn, _ToVsn, State) ->
    {ok, State}.

%% --------------------------------------------------------------------------------
%% -- helpers
reg_key(#ex_uri{scheme = "tcp", authority = #ex_uri_authority{host = Host, port = Port}}) ->
    {tcp, Host, Port};
reg_key(#ex_uri{scheme = "ipc", path = Path, authority = #ex_uri_authority{host = Host}}) ->
    case Host of
        undefined -> {ipc, Path};
        _         -> {ipc, filename:join(Host, Path)}
    end.