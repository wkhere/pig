%%-*-prolog-*-
:- use_module(library(http/dcg_basics)).

%% util

+dl(Xs-Ys, Ys-Zs, Xs-Zs).

list_to_dl(S,DL-E) :- append(S,E,DL).

%% lexer

eat(C, [C|Xs]) --> C, eat(C, Xs).
eat(C, [C]) --> C.

split([X|Xs]) --> nonblanks(X), {X\=[]}, whites, split(Xs).
split([]) --> [].

split_with1(Delimiter, [X|Xs]) -->
    string_without(Delimiter,X), {X\=[]}, Delimiter,
    split_with1(Delimiter, Xs).
split_with1(Delimiter, [LastX]) -->
    string_without(Delimiter,LastX), {LastX\=[]}.
split_with1(_Delimiter, []) --> [].

keys([K|Ks]) --> key(K), whites, keys(Ks).
keys([]) --> [].

key(key(K,V)) --> nonblanks(X), whites, values(V), {X\=[], atom_codes(K,X)}.

values(many(X)) --> bracketed(X), !. % X as list
values(one(S)) --> nonblanks(X), {string_to_list(S,X)}. % S as string

bracketed(S) --> "{", in_brackets(X-[]), "}", {string_to_list(S,X)}.

in_brackets(E-E) --> [].
in_brackets(Zs) --> "{", !, in_brackets(Xs), "}", in_brackets(Ys),
    {list_to_dl("{",B1), list_to_dl("}",B2),
    +dl(B1,Xs, Z1),
    +dl(Z1,B2, Z2),
    +dl(Z2,Ys, Zs)}.
in_brackets(Ys) -->
    string_without("{}",S), {S\=[]},
    in_brackets(Xs),
    {list_to_dl(S,X), +dl(X, Xs, Ys)}.

bracketed2(X) --> "{", in_brackets2(X), "}".

in_brackets2([]) --> [].
in_brackets2(Zs) --> "{", !, in_brackets2(Xs), "}", in_brackets2(Ys),
    {string_to_atom(B1,'{'), string_to_atom(B2,'}'),
    string_concat(B1,Xs, Z1),
    string_concat(Z1,B2, Z2),
    string_concat(Z2,Ys, Zs)}.
in_brackets2(Ys) -->
    string_without("{}",S), {S\=[]},
    in_brackets2(Xs),
    {string_to_list(X,S), string_concat(X, Xs, Ys)}.

%% parser

headline(headline(PkgName, Bytes)) --> 
    nonblanks(P), whites, integer(Bytes),
    {atom_codes(PkgName,P)}.
 
parse(_P, []).
parse(P, [K|Ks]) :- parse(P,K), parse(P,Ks).

parse(P, key(name, one(X))) :- string_to_atom(X,P).

parse(P, key(portdir, one(X))) :- assert( portdir(P, X) ).

parse(P, key(depends_fetch,   V)) :- parse_deps(P, dep_fetch,   V).
parse(P, key(depends_extract, V)) :- parse_deps(P, dep_extract, V).
parse(P, key(depends_build,   V)) :- parse_deps(P, dep_build,   V).
parse(P, key(depends_lib,     V)) :- parse_deps(P, dep_lib,     V).
parse(P, key(depends_run,     V)) :- parse_deps(P, dep_run,     V).

parse(_P, key(variants, _OneOrMany)). % todo

parse(_P, key(variant_desc, _OneOrMany)).

parse(P, key(description, many(D))) :- assert( description(P, D) ).
parse(P, key(description, one(D)))  :- assert( description(P, D) ).

parse(_P, key(homepage, _OneOrMany)).

parse(_P, key(platforms, _OneOrMany)).

parse(_P, key(license, _OneOrMany)).

parse(_P, key(replaced_by, _OneOrMany)).

parse(_P, key(epoch, one(_X))).

parse(_P, key(maintainers, _OneOrMany)).

parse(_P, key(long_description, _OneOrMany)).

parse(P, key(version, one(V))) :- assert( version(P, V) ).

parse(_P, key(revision, one(_X))).

parse(P, key(categories, one(C))) :-
    string_to_atom(C,A),
    assert( categories(P, [A]) ).
parse(P, key(categories, many(X))) :-
    string_to_list(X,S),
    phrase(split(Cs), S),
    findall(A, (member(C,Cs),atom_codes(A,C)), As),
    assert( categories(P, As) ).


parse_deps(P, DepType, many(DepsStr)) :-
    string_to_list(DepsStr, S), phrase(split(Ds), S),
    forall(member(D, Ds),  parse_dep(P, DepType, D)).
parse_deps(P, DepType, one(DepStr)) :-
    string_to_list(DepStr, D),
    parse_dep(P, DepType, D).

parse_dep(P, DepType, S) :-
    phrase(split_with1(":", Tokens), S),
    parse_dep_(P, DepType, Tokens).
parse_dep_(P, DepType, ["port",P1S]) :-
    atom_codes(P1,P1S),
    assert( dep(P, DepType, strict(port(P1))) ).
parse_dep_(P, DepType, ["lib",_FileS,P1S]) :-
    atom_codes(P1,P1S),
    assert( dep(P, DepType, lib(port(P1))) ).
parse_dep_(P, DepType, ["path",_PathS,P1S]) :-
    atom_codes(P1,P1S),
    assert( dep(P, DepType, path(port(P1))) ).
parse_dep_(P, DepType, ["bin",_PathS,P1S]) :-
    atom_codes(P1,P1S),
    assert( dep(P, DepType, bin(port(P1))) ).


%% feeder

eat_file :- eat_file('data/pi0').
eat_file(Fname) :- open(Fname, read, File), eat_lines(File).

eat_lines(File) :- eat_lines(File,0).
eat_lines(File,RecordCount) :-
    read_line_to_codes(File,S1),
    (S1 = end_of_file -> !;
        phrase(headline(headline(P,_Bytes)),S1),
        read_line_to_codes(File,S2),
        phrase(keys(Ks),S2),
        parse(P,Ks),
        RC1 is RecordCount+1,
        eat_lines(File,RC1)
    ).

freeze_db :-
    eat_file,
    compile_predicates([portdir/2, version/2, description/2]).
    %garbage_collect.
