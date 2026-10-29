$catalogs[0] as $c |
def fail($n;$s): {schema_version:1,operation:$q.operation,ok:false,exit_code:$n,reasons:[{code:$s}]};
def norm:
 capture("^(?<a>[0-9]+)\\.(?<b>[0-9]+)(?:\\.(?<c>[0-9]+))?-(?<d>[0-9]+)(?:-(?<e>[0-9]+))?$") |
 [.a,.b,(.c // "0"),.d,(.e // "0")] | map(tonumber) |
 "\(.[0]).\(.[1]).\(.[2])-\(.[3])-\(.[4])";
def modes:
 .modes | map(. as $m | . + {recipe:$c.recipes[.recipe_sha256],reasons:
   (if $c.recipes[.recipe_sha256]==null then [{code:"RECIPE_UNVERIFIED"}]
    elif (.cpu_flags|type)!="array" then [{code:"CPU_FEATURE_UNKNOWN"}]
    elif (.cpu_flags|length)>0 and ($q.cpu.flags_known != true) then [{code:"CPU_FEATURE_UNKNOWN"}]
    elif ((.cpu_flags - ($q.cpu.flags // []))|length)>0 then [{code:"CPU_FEATURE_MISSING"}]
    else [] end)}) ;
def result:
 . as $t | modes as $m |
 {schema_version:1,operation:$q.operation,catalog_id:$c.catalog_id,ok:true,exit_code:0,reasons:[],
 source_revisions:$c.sources,target:($t|del(.modes)),allowed_modes:[$m[]|select(.reasons==[])],rejected_modes:[$m[]|select(.reasons!=[])]};
def valid_target:
 (.model|type)=="string" and (.platform|type)=="string" and
 (.kernel|type)=="string" and (.kernel|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
 (.tuple|type)=="array" and (.tuple|length)==5 and
 all(.tuple[]; type=="number" and .>=0 and floor==.) and
 (.release == "\(.tuple[0]).\(.tuple[1]).\(.tuple[2])-\(.tuple[3])-\(.tuple[4])") and
 (.modes|type)=="array" and all(.modes[];
   . as $m | (["all-modules","custom-modules","anodrm-modules"]|index($m.module))!=null and
   (["IML","PML"]|index($m.method))!=null and .id==(.module+":"+.method) and
   (.cpu_flags|type)=="array" and all(.cpu_flags[];type=="string"));
if ($c.schema_version != 1 or ($c.targets|type)!="array" or ($c.recipes|type)!="object" or ($c.catalog_id|type)!="string" or $c.platform_policy.version != 1 or ($c.platform_policy.kernel5_platforms|type)!="array" or ($c.platform_policy.excluded_platforms|type)!="array" or ($c.platform_policy.dt_platforms|type)!="array") then fail(3;"CATALOG_INCONSISTENT")
elif (($c.platform_policy.excluded_platforms | index("epyc7003ntb")) == null or (($c.platform_policy.kernel5_platforms - $c.platform_policy.excluded_platforms)|length) != ($c.platform_policy.kernel5_platforms|length)) then fail(3;"CATALOG_INCONSISTENT")
elif (all($c.targets[];valid_target)|not) then fail(3;"CATALOG_INCONSISTENT")
elif any($c.targets[]; . as $t | (($c.platform_policy.excluded_platforms | index($t.platform)) != null) or (($t.kernel | startswith("5.")) and (($c.platform_policy.kernel5_platforms | index($t.platform)) == null))) then fail(3;"CATALOG_INCONSISTENT")
elif (["identity","options","list","validate"]|index($q.operation))==null or ($q.model|type)!="string" then fail(2;"INVALID_REQUEST")
else
 [$c.targets[]|select(.model==$q.model and .channel==($q.channel // "stable"))] as $ts |
 if $q.operation=="list" then
 {schema_version:1,operation:"list",catalog_id:$c.catalog_id,ok:true,exit_code:0,reasons:[],
 targets:[$ts[]|select(.status=="inherited-supported" or .status=="verified")|result|select(.allowed_modes|length>0)]|sort_by(.target.tuple)|reverse}
 else ((try ($q.release|norm) catch null) // null) as $r |
 if $r==null then fail(2;"INVALID_RELEASE")
 else [$ts[]|select(.release==$r)] as $found |
 if ($found|length)!=1 then fail(4;"MODEL_RELEASE_UNSUPPORTED")
 else $found[0] |
 if $q.operation=="identity" then {schema_version:1,operation:"identity",catalog_id:$c.catalog_id,ok:true,exit_code:0,reasons:[],target:(del(.modes))}
 elif (.status!="inherited-supported" and .status!="verified") then fail(5;"TARGET_NOT_APPROVED")
 else result |
 if $q.operation=="validate" then
 . as $out | [.allowed_modes[]|select(.module==$q.mode.module and .method==$q.mode.method)] as $selected |
 if ($selected|length)==1 then . + {selected_mode:$selected[0]} | del(.allowed_modes,.rejected_modes)
 else (first(.rejected_modes[]|select(.module==$q.mode.module and .method==$q.mode.method)) // null) as $bad |
 . + {ok:false,exit_code:5,reasons:($bad.reasons // [{code:"MODE_UNAVAILABLE"}])} end
 else . end end end end end end
