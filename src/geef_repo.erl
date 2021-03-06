%%%-------------------------------------------------------------------
%%% @author Carlos Martín Nieto <cmn@dwim.me>
%%% @copyright (C) 2013, Carlos Martín Nieto
%%% @doc
%%%
%%% @end
%%% Created :  6 Apr 2013 by Carlos Martín Nieto <cmn@dwim.me>
%%%-------------------------------------------------------------------
-module(geef_repo).

-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% API
-export([open/1, init/2, path/1, workdir/1, odb/1, is_bare/1, references/1, discover/1,
	 lookup_object/2, lookup_reference/2, create_reference/4, revwalk/1, stop/1,
	 reference_dwim/2, handle/1]).

-include("geef_records.hrl").
-record(state, {handle}).


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Discover a repository's path from a path contained inside it
-spec discover(iolist()) -> {ok, binary()} | error | {error, term()}.
discover(Path) ->
    geef_nif:repository_discover(Path).

%% @doc Open an existing repository. Path must point to the git-dir or
%% worktree
-spec open(iolist()) -> {ok, pid()} | {error, term()}.
open(Path) ->
    case geef_nif:repository_open(Path) of
	{ok, Handle} ->
	    start_link(Handle);
	Other ->
	    Other
    end.

%% @doc Initialize a new repository
-spec init(iolist(), boolean()) -> {ok, pid()} | {error, term()}.
init(Path, Bare) ->
    case geef_nif:repository_init(Path, Bare) of
	{ok, Handle} ->
	    start_link(Handle);
	Other ->
	    Other
    end.	

%% @doc The repository's git-dir path
-spec path(pid()) -> binary().
path(Pid) ->
    gen_server:call(Pid, path).

%% @doc The repository's worktree path
-spec workdir(pid()) -> binary().
workdir(Pid) ->
    gen_server:call(Pid, workdir).

%% @doc The repository's current object database. This encompasses all
%% the configured backends.
-spec odb(pid()) -> {ok, pid()} | {error, term}.
odb(Pid) ->
    gen_server:call(Pid, odb).

%% @doc Whether the repository is bare
-spec is_bare(pid()) -> boolean().
is_bare(Pid) ->
    gen_server:call(Pid, bare).

%% @doc List of references in the repository.
-spec references(pid()) -> [binary()].
references(Pid) ->
    gen_server:call(Pid, refs).

lookup_object(Pid, Oid) ->
    gen_server:call(Pid, {lookup_object, Oid}).

%% @private
lookup_reference(Pid, Name) ->
    gen_server:call(Pid, {lookup_reference, Name}).

%% @private
reference_dwim(Pid, Name) ->
    gen_server:call(Pid, {dwim_reference, Name}).

%% @private
create_reference(Pid, Name, Target, Force) ->
    gen_server:call(Pid, {create_reference, Name, Target, Force}).

%% @doc Create a revision walker for the given repository.
revwalk(Pid) ->
    gen_server:call(Pid, revwalk).

stop(Pid) ->
    gen_server:call(Pid, stop).

%% @private
%% @doc Get the underlying repo resource6
handle(Pid) ->
    gen_server:call(Pid, handle).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init(Handle) ->
    {ok, #state{handle=Handle}}.

%% @private
handle_call(path, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:repository_get_path(Handle),
    {reply, Reply, State};
handle_call(workdir, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:repository_get_workdir(Handle),
    {reply, Reply, State};
handle_call(odb, _From, State = #state{handle=Handle}) ->
    Reply = handle_odb(Handle),
    {reply, Reply, State};
handle_call(bare, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:repository_is_bare(Handle),
    {reply, Reply, State};
handle_call(refs, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:reference_list(Handle),
    {reply, Reply, State};
handle_call({lookup_object, Oid}, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:object_lookup(Handle, Oid),
    {reply, Reply, State};
handle_call({lookup_reference, Name}, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:reference_lookup(Handle, Name),
    {reply, Reply, State};
handle_call({dwim_reference, Name}, _From, State = #state{handle=Handle}) ->
    Reply = geef_nif:reference_dwim(Handle, Name),
    {reply, Reply, State};
handle_call({create_reference, Name, Target, Force}, _From, State = #state{handle=Handle}) ->
    Reply = handle_create_reference(Handle, Name, Target, Force),
    {reply, Reply, State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(revwalk, _From, State = #state{handle=Handle}) ->
    Reply = handle_revwalk(Handle),
    {reply, Reply, State};
handle_call(handle, _From, State = #state{handle=Handle}) ->
    {reply, Handle, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%==================================================================

-spec start_link(term()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Handle) ->
    gen_server:start_link(?MODULE, Handle, []).

handle_odb(Handle) ->
    case geef_nif:repository_get_odb(Handle) of
	{ok, OdbHandle} ->
	    geef_odb:start_link(OdbHandle);
	Other ->
	    Other
    end.

handle_revwalk(Handle) ->
    case geef_nif:revwalk_new(Handle) of
	{ok, WalkHandle} ->
	    geef_revwalk:start_link(WalkHandle);
	Error ->
	    Error
    end.

handle_create_reference(Repo, Refname, #geef_oid{oid=Oid}, Force) ->
     geef_nif:reference_create(Repo, Refname, oid, Oid, Force);
handle_create_reference(Repo, Refname, Target, Force) ->
    geef_nif:reference_create(Repo, Refname, symbolic, Target, Force).
