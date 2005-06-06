(* camlp4r ./pa_html.cmo *)
(* $Id: notes.ml,v 4.42 2005-06-06 12:20:59 ddr Exp $ *)

open Config;
open Def;
open Gutil;
open Util;

(* TLSW: Text Language Stolen to Wikipedia
   = title level 1 =
   == title level 2 ==
   ...
   ====== title level 6 ======
   * list ul/li item
   * list ul/li item
   ** list ul/li item 2nd level
   ** list ul/li item 2nd level
   ...
   [[first_name/surname/oc/text]] link; 'text' displayed
   [[first_name/surname/text]] link (oc = 0); 'text' displayed
   [[first_name/surname]] link (oc = 0) ; 'first_name surname' displayed *)

module Buff = Buff.Make (struct value buff = ref (String.create 80); end);

value first_cnt = 1;

value tab lev s = String.make (2 * lev) ' ' ^ s;

value rec syntax_lists conf list =
  fun
  [ [s :: sl] ->
      if String.length s > 0 && s.[0] = '*' then
        let (sl, rest) = select_list_lines conf [] [s :: sl] in
        let list = syntax_ul 0 list sl in
        syntax_lists conf list rest
      else syntax_lists conf [s :: list] sl
  | [] -> List.rev list ]
and select_list_lines conf list =
  fun
  [ [s :: sl] ->
      let len = String.length s in
      if len > 0 && s.[0] = '*' then
        let s = String.sub s 1 (len - 1) in
        let (s, sl) =
          loop s sl where rec loop s1 =
            fun
            [ [""; s :: sl]
              when String.length s > 1 && s.[0] = '*' && s.[1] = '*' ->
                let br = "<br" ^ conf.xhs ^ ">" in
                loop (s1 ^ br ^ br) [s :: sl]
            | [s :: sl] ->
                if String.length s > 0 && s.[0] <> '*' then
                  loop (s1 ^ "\n" ^ s) sl
                else (s1, [s :: sl])
            | [] -> (s1, []) ]
        in
        select_list_lines conf [s :: list] sl
      else (List.rev list, [s :: sl])
  | [] -> (List.rev list, []) ]
and syntax_ul lev list sl =
  let list = [tab lev "<ul>" :: list] in
  let list =
    loop list sl where rec loop list =
      fun
      [ [s1; s2 :: sl] ->
          if String.length s2 > 0 && s2.[0] = '*' then
            let list = [tab lev "<li>" ^ s1 :: list] in
            let (list2, sl) =
              loop [] [s2 :: sl] where rec loop list =
                fun
                [ [s :: sl] ->
                    if String.length s > 0 && s.[0] = '*' then
                      let s = String.sub s 1 (String.length s - 1) in
                      loop [s :: list] sl
                    else (list, [s :: sl])
                | [] -> (list, []) ]
            in
            let list = syntax_ul (lev + 1) list (List.rev list2) in
            loop [tab lev "</li>" :: list] sl
          else
            loop [tab lev "<li>" ^ s1 ^ "</li>" :: list] [s2 :: sl]
      | [s] -> [tab lev "<li>" ^ s ^ "</li>" :: list]
      | [] -> list ]
  in
  [tab lev "</ul>" :: list]
;

value rev_syntax_lists conf list rev_list =
  syntax_lists conf list (List.rev rev_list)
;

value syntax_links conf s =
  let slen = String.length s in
  loop 0 0 where rec loop i len =
    if i = slen then Buff.get len
    else if i < slen - 1 && s.[i] = '[' && s.[i+1] = '[' then
      let j =
        loop (i + 2) where rec loop j =
          if j = slen then j
          else if j < slen - 1 && s.[j] = ']' && s.[j+1] = ']' then j + 2
          else loop (j + 1)
      in
      let t =
        let b = String.sub s (i + 2) (j - i - 4) in
        try
          let k = 0 in
          let l = String.index_from b k '/' in
          let fn = String.sub b k (l - k) in
          let k = l + 1 in
          let (fn, sn, oc, name) =
            try
              let l = String.index_from b k '/' in
              let sn = String.sub b k (l - k) in
              let (oc, name) =
                try
                  let k = l + 1 in
                  let l = String.index_from b k '/' in
                  let x = String.sub b k (l - k) in
                  (x, String.sub b (l + 1) (String.length b - l - 1))
                with
                [ Not_found ->
                    ("", String.sub b (l + 1) (String.length b - l - 1)) ]
              in
              (fn, sn, oc, name)
            with
            [ Not_found ->
                let sn = String.sub b k (String.length b - k) in
                let name = fn ^ " " ^ sn in
                (fn, sn, "", name) ]
          in
          Printf.sprintf "<a href=\"%sp=%s;n=%s%s\">%s</a>" (commd conf)
            (code_varenv (Name.lower fn)) (code_varenv (Name.lower sn))
            (if oc = "" then "" else ";oc=" ^ oc) name
        with
        [ Not_found -> "[[" ^ b ^ "]]" ]
      in
      loop j (Buff.mstore len t)
    else loop (i + 1) (Buff.store len s.[i])
;

value section_level s len =
  loop 1 (len - 2) 4 where rec loop i j k =
    if i > 5 then i
    else if len > k && s.[i] = '=' && s.[j] = '=' then
      loop (i + 1) (j - 1) (k + 2)
    else i
;

value lines_list_of_string s =
  loop [] 0 0 where rec loop lines len i =
    if i = String.length s then
      List.rev (if len = 0 then lines else [Buff.get len :: lines])
    else if s.[i] = '\n' then loop [Buff.get len :: lines] 0 (i + 1)
    else loop lines (Buff.store len s.[i]) (i + 1)
;

value insert_sub_part s v sub_part =
  let lines = lines_list_of_string s in
  let (lines, sl) =
    loop False [] 0 first_cnt lines
    where rec loop sub_part_added lines lev cnt =
      fun
      [ [s :: sl] ->
          let len = String.length s in
          if len > 2 && s.[0] = '=' && s.[len-1] = '=' then
            if v = first_cnt - 1 then ([""; sub_part], [s :: sl])
            else
              let nlev = section_level s len in
              if cnt = v then
                loop True [""; sub_part :: lines] nlev (cnt + 1) sl
              else if cnt > v then
                if nlev > lev then loop sub_part_added lines lev (cnt + 1) sl
                else (lines, [s :: sl])
              else loop sub_part_added [s :: lines] lev (cnt + 1) sl
            else if cnt <= v then loop sub_part_added [s :: lines] lev cnt sl
            else loop sub_part_added lines lev cnt sl
      | [] ->
          let lines =
            if sub_part_added then lines else [""; sub_part :: lines]
          in
          (lines, []) ]
  in
  String.concat "\n" (List.rev_append lines sl)
;

value rev_extract_sub_part s v =
  let lines = lines_list_of_string s in
  loop [] 0 first_cnt lines where rec loop lines lev cnt =
    fun
    [ [s :: sl] ->
        let len = String.length s in
        if len > 2 && s.[0] = '=' && s.[len-1] = '=' then
          if v = first_cnt - 1 then lines
          else
            let nlev = section_level s len in
            if cnt = v then loop [s :: lines] nlev (cnt + 1) sl
            else if cnt > v then
              if nlev > lev then loop [s :: lines] lev (cnt + 1) sl
              else lines
            else loop lines lev (cnt + 1) sl
        else if cnt <= v then loop lines lev cnt sl
        else loop [s :: lines] lev cnt sl
    | [] -> lines ]
;

value extract_sub_part s v =
  let rev_lines = rev_extract_sub_part s v in
  String.concat "\n" (List.rev rev_lines)
;

value summary_of_tlsw_lines conf lines =
  let (rev_summary, lev, _, _) =
    let ul = "<ul style=\"list-style:none\">" in
    List.fold_left
      (fun (summary, lev, indent_stack, cnt) s ->
        let len = String.length s in
        if len > 2 && s.[0] = '=' && s.[len-1] = '=' then
          let slev = section_level s len in
          let (summary, lev, stack) =
            loop summary lev indent_stack where rec loop summary lev stack =
              match stack with
              [ [(prev_num, prev_slev) :: rest_stack] ->
                  if slev < prev_slev then
                    match rest_stack with
                    [ [(_, prev_prev_slev) :: _] ->
                        if slev > prev_prev_slev then
                          let stack = [(prev_num + 1, slev) :: rest_stack] in
                          loop summary lev stack
                        else
                          let summary = [tab (lev - 1) "</li>" :: summary] in
                          let summary = [tab (lev - 1) "</ul>" :: summary] in
                          loop summary (lev - 1) rest_stack
                    | [] ->
                        let summary = [tab (lev - 1) "</li>" :: summary] in
                        let stack = [(prev_num + 1, slev) :: rest_stack] in
                        (summary, lev - 1, stack) ]
                  else if slev = prev_slev then
                    let summary = [tab (lev - 1) "</li>" :: summary] in
                    let stack = [(prev_num + 1, slev) :: rest_stack] in
                    (summary, lev - 1, stack)
                  else
                    let summary = [tab lev ul :: summary] in
                    let stack = [(1, slev) :: stack] in
                    (summary, lev, stack)
              | [] ->
                  let summary = [tab lev ul :: summary] in
                  let stack = [(1, slev) :: stack] in
                  (summary, lev, stack) ]
          in
          let summary = [tab lev "<li>" :: summary] in
          let s =
            let nums = List.map fst stack in
            Printf.sprintf "<a href=\"#a_%d\">%s %s</a>"
              cnt (String.concat "." (List.rev_map string_of_int nums))
              (String.sub s slev (len - 2 * slev))
          in
          let summary = [tab (lev + 1) s :: summary] in
          (summary, lev + 1, stack, cnt + 1)
        else (summary, lev, indent_stack, cnt))
      ([], 0, [], first_cnt) lines
  in
  let rev_summary =
    loop lev rev_summary where rec loop lev summary =
      if lev > 0 then
        let summary = [tab (lev - 1) "</li>" :: summary] in
        let summary = [tab (lev - 1) "</ul>" :: summary] in
        loop (lev - 1) summary
      else summary
  in
  if rev_summary <> [] then
    ["<dl><dd>";
     "<table border=\"1\"><tr><td>";
     "<table><tr>";
     "<td align=\"center\"><b>" ^ capitale (transl conf "summary") ^
       "</b></td>";
     "</tr><tr><td>" ::
     List.rev_append rev_summary
       ["</td><td>";
        "<ul style=\"list-style:none\"><li>&nbsp;</li></ul>";
        "</td></tr></table"; "</td></tr></table>";
        "</dd></dl>"]]
  else []
;

value html_of_tlsw_lines conf cnt0 lines =
  let (rev_lines, _) =
    List.fold_left
      (fun (lines, cnt) s ->
         let len = String.length s in
         if len > 2 && s.[0] = '=' && s.[len-1] = '=' then
           let lev = section_level s len in
           let s =
             Printf.sprintf "<h%d>%s%s</h%d>" lev
               (String.sub s lev (len-2*lev))
               (if lev <= 3 then "<hr" ^ conf.xhs ^ ">" else "") lev
           in
           let n1 =
             if conf.wizard then
               Printf.sprintf
                 "<div style=\"float:right;margin-left:5px\">\
                  (<a href=\"%sm=MOD_NOTES;v=%d\">%s</a>)</div>"
                 (commd conf) cnt (transl_decline conf "modify" "")
             else ""
           in
           let n2 =
             Printf.sprintf "<p><a name=\"a_%d\" id=\"a_%d\"></a></p>"
               cnt cnt
           in
           ([s; n1; n2 :: lines], cnt + 1)
         else ([s :: lines], cnt))
      ([], max cnt0 first_cnt) lines
  in
  rev_syntax_lists conf [] rev_lines
;

value html_with_summary_of_tlsw conf s =
  let lines = lines_list_of_string s in
  let summary = summary_of_tlsw_lines conf lines in
  let (rev_lines_before_summary, lines) =
    loop [] lines where rec loop lines_bef =
      fun
      [ [s :: sl] ->
          if String.length s > 1 && s.[0] = '=' then (lines_bef, [s :: sl])
          else loop [s :: lines_bef] sl
      | [] -> (lines_bef, []) ]
  in
  let lines_before_summary =
    rev_syntax_lists conf [] rev_lines_before_summary
  in
  let lines_after_summary = html_of_tlsw_lines conf first_cnt lines in
  let s =
    syntax_links conf
      (String.concat "\n"
        (lines_before_summary @ summary @ lines_after_summary))
  in
  if conf.wizard then
    Printf.sprintf "%s(<a href=\"%sm=MOD_NOTES;v=0\">%s</a>)%s\n"
      (if s = "" then "<p>" else "<div style=\"float:right;margin-left:5px\">")
      (commd conf) (transl_decline conf "modify" "")
      (if s = "" then "</p>" else "</div>") ^
    s
  else s
;

value navigate mode conf cnt0 test_end =
  tag "p" begin
    if cnt0 >= first_cnt then do {
      stag "a" "href=\"%sm=%s;v=%d\"" (commd conf) mode (cnt0 - 1) begin
        Wserver.wprint "&lt;&lt;";
      end;
      Wserver.wprint "\n";
    }
    else ();
    if cnt0 >= first_cnt - 1 then do {
      stag "a" "href=\"%sm=%s\"" (commd conf) mode begin
        Wserver.wprint "^^";
      end;
      Wserver.wprint "\n";
    }
    else ();
    if test_end then do {
      stag "a" "href=\"%sm=%s;v=%d\"" (commd conf) mode (cnt0 + 1) begin
        Wserver.wprint "&gt;&gt;";
      end;
      Wserver.wprint "\n";
    }
    else ();
  end
;

value print_sub_part conf cnt0 lines =
  let lines = html_of_tlsw_lines conf cnt0 lines in
  let s = syntax_links conf (String.concat "\n" lines) in
  let s = string_with_macros conf False [] s in
  let s =
    if cnt0 < first_cnt && conf.wizard then
      Printf.sprintf "%s(<a href=\"%sm=MOD_NOTES;v=0\">%s</a>)%s\n"
        (if s = "" then "<p>"
         else "<div style=\"float:right;margin-left:5px\">")
        (commd conf) (transl_decline conf "modify" "")
        (if s = "" then "</p>" else "</div>") ^
      s
    else s
  in
  do {
    navigate "NOTES" conf cnt0 (lines <> []);
    Wserver.wprint "%s\n" s
  }
;

value print conf base =
  let title _ =
    Wserver.wprint "%s - %s"
      (capitale (nominative (transl_nth conf "note/notes" 1))) conf.bname
  in
  let s = base.data.bnotes.nread 0 in
  do {
    header_no_page_title conf title;
    print_link_to_welcome conf False;
    html_p conf;
    match p_getint conf.env "v" with
    [ Some cnt0 ->
        let lines = List.rev (rev_extract_sub_part s cnt0) in
        print_sub_part conf cnt0 lines
    | None ->
        let s = html_with_summary_of_tlsw conf s in
        let s = string_with_macros conf False [] s in
        Wserver.wprint "%s\n" s ];
    trailer conf;
  }
;

value print_mod conf base =
  let title _ =
    let s = transl_nth conf "note/notes" 1 in
    Wserver.wprint "%s - %s" (capitale (transl_decline conf "modify" s))
      conf.bname
  in
  let s = base.data.bnotes.nread 0 in
  let (has_v, v) =
    match p_getint conf.env "v" with
    [ Some v -> (True, v)
    | None -> (False, 0) ]
  in
  let sub_part = if not has_v then s else extract_sub_part s v in
  do {
    header conf title;
    tag "div" "style=\"float:right;margin-left:5px\"" begin
      stag "a" "href=\"%sm=NOTES%s\"" (commd conf)
        (if has_v then ";v=" ^ string_of_int v else "")
      begin
        Wserver.wprint "(%s)\n" (transl conf "visualize");
      end;
    end;
    print_link_to_welcome conf False;
    if has_v then navigate "MOD_NOTES" conf v (sub_part <> "") else ();
    tag "form" "method=\"post\" action=\"%s\"" conf.command begin
      tag "p" begin
        Util.hidden_env conf;
        xtag "input" "type=\"hidden\" name=\"m\" value=\"MOD_NOTES_OK\"";
        if has_v then
          xtag "input" "type=\"hidden\" name=\"v\" value=\"%d\"" v
        else ();
        let digest = Iovalue.digest s in
        xtag "input" "type=\"hidden\" name=\"digest\" value=\"%s\"" digest;
        stagn "textarea" "name=\"notes\" rows=\"30\" cols=\"110\"" begin
          if sub_part <> "" then Wserver.wprint "%s" (quote_escaped sub_part)
          else ();
        end;
      end;
      tag "p" begin
        xtag "input" "type=\"submit\" value=\"Ok\"";
      end;
    end;
    trailer conf;
  }
;

value print_ok conf base s =
  let title _ =
    Wserver.wprint "%s" (capitale (transl conf "notes modified"))
  in
  do {
    header conf title;
    print_link_to_welcome conf True;
    let get_v = p_getint conf.env "v" in
    let (has_v, v) =
      match get_v with
      [ Some v -> (True, v)
      | None -> (False, 0) ]
    in
    History.record_notes conf base get_v "mn";
    if has_v then print_sub_part conf v (lines_list_of_string s)
    else
      Wserver.wprint "<a href=\"%sm=NOTES\">%s</a>\n" (commd conf)
        (capitale (transl_nth conf "note/notes" 1));
    trailer conf
  }
;

value print_mod_ok conf base =
  let sub_part =
    match p_getenv conf.env "notes" with
    [ Some v -> strip_all_trailing_spaces v
    | None -> failwith "notes unbound" ]
  in
  let digest =
    match p_getenv conf.env "digest" with
    [ Some s -> s
    | None -> "" ]
  in
  let old_notes = base.data.bnotes.nread 0 in
  try
    if digest <> Iovalue.digest old_notes then Update.error_digest conf base
    else
      let s =
        match p_getint conf.env "v" with
        [ Some v -> insert_sub_part old_notes v sub_part
        | None -> sub_part ]
      in
      do { base.func.commit_notes s; print_ok conf base sub_part }
  with
  [ Update.ModErr -> () ]
;
