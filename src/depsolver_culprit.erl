%% -*- erlang-indent-level: 4; indent-tabs-mode: nil; fill-column: 80 -*-
%% ex: ts=4 sx=4 et
%%%-------------------------------------------------------------------
%%% @author Eric Merritt <ericbmerritt@gmail.com>
%%% @doc
%%%  This app does the culprit search for a failed solve. It searches
%%%  through the goals provided by the user trying to find the first one
%%%  that fails. It then returns that as the culprit along with the
%%%  unknown apps from the goal, the version constrained apps from the
%%%  goal, and the good apps (those not immediately constrained from
%%%  the goals).
%%% @end
-module(depsolver_culprit).

-export([search/3,
        format_error/1]).

-export_type([detail/0]).

%%============================================================================
%% Types
%%============================================================================
-type detail() :: {UnknownApps::[depsolver:constraint()],
                   VersionConstrained::[depsolver:constraint()],
                   GoodApps::[depsolver:constraint()]}.

%%============================================================================
%% Internal API
%%============================================================================
%% @doc start running the solver, with each run reduce the number of constraints
%% set as goals. At some point the solver should succeed.
-spec search(depsolver:dep_graph(), [depsolver:constraint()], [depsolver:constraint()])
            -> detail() | term().
search(State, ActiveCons, []) ->
    case depsolver:primitive_solve(State, ActiveCons, keep_paths) of
        {fail, FailPaths} ->
            format_culprit_error(ActiveCons, lists:flatten(FailPaths), []);
        _Success ->
            %% This should *never* happen. 'Culprit' above represents the last
            %% possible constraint that could cause things to fail. There for
            %% this should have failed as well.
            inconsistant_graph_state
    end;
search(State, ActiveCons, [NewCon | Constraints]) ->
    case depsolver:primitive_solve(State, ActiveCons, keep_paths) of
        {fail, FailPaths} ->
            format_culprit_error(ActiveCons, lists:flatten(FailPaths), []);
        _Success ->
            %% Move one constraint from the inactive to the active
            %% constraints and run again
            search(State, [NewCon | ActiveCons], Constraints)
    end.

format_error({error, Detail}) ->
    format_error(Detail);
format_error(Details) when erlang:is_list(Details) ->
    ["Unable to solve constraints, the following solutions were attempted \n\n",
     [[format_error_path("    ", Detail)] || Detail <- Details]].

%%============================================================================
%% Internal Functions
%%============================================================================
append_value(Key, Value, PropList) ->
    case proplists:get_value(Key, PropList, undefined) of
        undefined ->
            [{Key, Value} | PropList];
        ExistingValue ->
            [{Key, sets:to_list(sets:from_list([Value | ExistingValue]))} |
             proplists:delete(Key, PropList)]
    end.

strip_goal([{'_GOAL_', 'NO_VSN'}, Children]) ->
    Children;
strip_goal(All = [Val | _])
  when erlang:is_list(Val) ->
    [strip_goal(Element) || Element <- All];
strip_goal(Else) ->
    Else.

format_culprit_error(_ActiveCons, [], Acc) ->
    Acc;
format_culprit_error(ActiveCons, [{[], RawConstraints} | Rest], Acc) ->
    %% In this case where there was no realized versions, the GOAL
    %% constraints actually where unsatisfiable
    Constraints = lists:flatten(lists:map(fun({_, Constraints}) ->
                                                  Constraints
                                          end, RawConstraints)),
    Cons = [Pkg || {Pkg, Src} <- Constraints,
                   Src =:= {'_GOAL_', 'NO_VSN'}],
    format_culprit_error(ActiveCons, Rest, [{[{Cons, Cons}], []} | Acc]);
format_culprit_error(ActiveCons, [{Path, RawConstraints} | Rest], Acc) ->
    Constraints = lists:flatten(lists:map(fun({_, Constraints}) ->
                                                  Constraints
                                          end, RawConstraints)),
    FailCons =
        lists:foldl(fun(El = {FailedPkg, FailedVsn}, Acc1) ->
                            case get_constraints(FailedPkg, FailedVsn, Path,
                                                 Constraints) of
                                [] ->
                                    Acc1;
                                Cons ->
                                    append_value(El, Cons, Acc1)
                            end
                    end, [], lists:reverse(Path)),
    TreedPath = strip_goal(treeize_path({'_GOAL_', 'NO_VSN'}, Constraints, [])),
    RunListItems = lists:map(fun(TPath = [PRoot | _]) ->
                                     RootName = depsolver:dep_pkg(PRoot),
                                     Roots = lists:filter(fun(El) ->
                                                                  RootName =:= depsolver:dep_pkg(El)
                                                          end, ActiveCons),
                                     {Roots, TPath}
                             end, TreedPath),
    Resolution = {RunListItems, FailCons},
    format_culprit_error(ActiveCons, Rest, [Resolution | Acc]);
format_culprit_error(ActiveCons, BareFailPath, Acc) when is_tuple(BareFailPath) ->
    format_culprit_error(ActiveCons, [BareFailPath], Acc).

follow_chain(Pkg, Vsn, {{Pkg, Vsn}, {Pkg, Vsn}}) ->
    %% When the package version is the same as the source we dont want to try to follow it at all
    false;
follow_chain(Pkg, Vsn, {Con, {Pkg, Vsn}}) ->
    {ok, Con};
follow_chain(_Pkg, _Vsn, _) ->
    false.

find_chain(Pkg, Vsn, Constraints) ->
    lists:foldl(fun(NCon, Acc) ->
                        case follow_chain(Pkg, Vsn, NCon) of
                            {ok, Con} ->
                                [Con | Acc];
                            false ->
                                Acc
                        end
                end, [], Constraints).

get_constraints(FailedPkg, FailedVsn, Path, Constraints) ->
    Chain = find_chain(FailedPkg, FailedVsn, Constraints),
    lists:filter(fun(Con) ->
                         PkgName = depsolver:dep_pkg(Con),
                         (lists:any(fun(PathEl) ->
                                            not depsolver:filter_package(PathEl, Con)
                                    end, Path) orelse
                          not lists:keymember(PkgName, 1, Path))
                 end, Chain).

pkg_vsn(PkgCon, Constraints) ->
    PkgName = depsolver:dep_pkg(PkgCon),
    [DepPkg || Con = {DepPkg, _} <- Constraints,
               case Con of
                   {Pkg = {PkgName, PkgVsn}, {PkgName, PkgVsn}} ->
                       depsolver:filter_package(Pkg, PkgCon);
                   _ ->
                       false
               end].

depends(SrcPkg, Constraints, Seen) ->
    lists:flatten([pkg_vsn(Pkg, Constraints) || {Pkg, Source} <- Constraints,
                                                Source =:= SrcPkg andalso
                                                    Pkg =/= SrcPkg andalso
                                                    not lists:member(Pkg, Seen)]).

treeize_path(Pkg, Constraints, Seen0) ->
    Seen1 = [Pkg | Seen0],
    case depends(Pkg, Constraints, Seen1) of
        [] ->
            [Pkg];
        Deps ->
            [Pkg,  [treeize_path(Dep, Constraints, Seen1) ||
                             Dep <- Deps]]

    end.

format_version({Maj}) ->
    erlang:integer_to_list(Maj);
format_version({Maj, Min}) ->
    [erlang:integer_to_list(Maj), ".",
     erlang:integer_to_list(Min)];
format_version({Maj, Min, Patch}) ->
    [erlang:integer_to_list(Maj), ".",
     erlang:integer_to_list(Min), ".",
     erlang:integer_to_list(Patch)].


-spec format_constraint(depsolver:constraint()) -> list().
format_constraint(Pkg) when is_atom(Pkg) ->
    erlang:atom_to_list(Pkg);
format_constraint(Pkg) when is_binary(Pkg) ->
    Pkg;
format_constraint({Pkg, Vsn}) when is_tuple(Vsn) ->
    ["(", format_constraint(Pkg), " = ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '='}) when is_tuple(Vsn) ->
    ["(", format_constraint(Pkg), " = ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, gte}) ->
    ["(", format_constraint(Pkg), " >= ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '>='}) ->
    ["(", format_constraint(Pkg), " >= ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, lte}) ->
    ["(", format_constraint(Pkg), " <= ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '<='}) ->
    ["(", format_constraint(Pkg), " <= ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, gt}) ->
    ["(", format_constraint(Pkg), " > ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '>'}) ->
    ["(", format_constraint(Pkg), " > ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, lt}) ->
    ["(", format_constraint(Pkg), " < ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '<'}) ->
    ["(", format_constraint(Pkg), " < ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, pes}) ->
    ["(", format_constraint(Pkg), " ~> ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn, '~>'}) ->
    ["(", format_constraint(Pkg), " ~> ",
     format_version(Vsn), ")"];
format_constraint({Pkg, Vsn1, Vsn2, between}) ->
    ["(", format_constraint(Pkg), " between ",
     format_version(Vsn1), " and ",
     format_version(Vsn2), ")"].

add_s(Roots) ->
     case erlang:length(Roots) of
         Len when Len > 1 ->
             "s";
         _ ->
             ""
     end.

format_roots(Roots) ->
    lists:foldl(fun(Root, Acc0) ->
                        lists:foldl(
                          fun(Con, "") ->
                                  [format_constraint(Con)];
                             (Con, Acc1) ->
                                  [format_constraint(Con), ", "  | Acc1]
                          end, Acc0, Root)
                end, "", Roots).

format_culprits(FailingDeps) ->
    Deps = sets:to_list(sets:from_list(lists:flatten([[depsolver:dep_pkg(Con) || Con <- Cons]
                                                      || {_, Cons} <- FailingDeps]))),
    lists:foldl(fun(Con, "") ->
                        [format_constraint(Con)];
                   (Con, Acc1) ->
                        [format_constraint(Con),
                        ", " | Acc1]
                end, "", Deps).


format_path(CurrentIdent, Path) ->
    [CurrentIdent, "    ",
     lists:foldl(fun(Con, "") ->
                         [format_constraint(Con)];
                    (Con, Acc) ->
                         [format_constraint(Con), " -> " | Acc]
                 end, "", Path),
     "\n"].

format_dependency_paths(CurrentIndent, [SubPath | Rest], FailingDeps, Acc)
  when erlang:is_list(SubPath) ->
    [format_dependency_paths(CurrentIndent, lists:sort(SubPath), FailingDeps, Acc),
     format_dependency_paths(CurrentIndent, Rest, FailingDeps, Acc)];
format_dependency_paths(CurrentIndent, [Dep], FailingDeps, Acc)
  when erlang:is_tuple(Dep) ->
    case proplists:get_value(Dep, FailingDeps, undefined) of
        undefined ->
            format_path(CurrentIndent, [Dep | Acc]);
        Cons ->
            [format_path(CurrentIndent, [Con, Dep | Acc]) || Con <- Cons]
    end;
format_dependency_paths(CurrentIndent, [Dep | Rest], FailingDeps, Acc)
  when erlang:is_tuple(Dep) ->
    case proplists:get_value(Dep, FailingDeps, undefined) of
        undefined ->
            format_dependency_paths(CurrentIndent, Rest, FailingDeps, [Dep | Acc]);
        Cons ->
            [[format_path(CurrentIndent, [Con, Dep | Acc]) || Con <- Cons],
             format_dependency_paths(CurrentIndent, Rest, FailingDeps, [Dep | Acc])]
    end;
format_dependency_paths(CurrentIndent, [Con | Rest], FailingDeps, Acc) ->
    format_dependency_paths(CurrentIndent, Rest, FailingDeps, [Con | Acc]);
format_dependency_paths(_CurrentIndent, [], _FailingDeps, _Acc) ->
    [].

format_error_path(CurrentIndent, {RawPaths, FailingDeps}) ->
    Roots = [RootSet || {RootSet, _} <- RawPaths],
    Paths = [Path || {_, Path} <- RawPaths],
    [CurrentIndent, "Unable to satisfy goal constraint",
     add_s(Roots), " ", format_roots(Roots), " due to constraint", add_s(FailingDeps), " on ",
     format_culprits(FailingDeps), "\n",
     format_dependency_paths(CurrentIndent, lists:sort(Paths), FailingDeps, []), ""].
