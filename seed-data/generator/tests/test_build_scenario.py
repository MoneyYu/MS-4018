import importlib.util
import io
import json
import os
import time
from pathlib import Path

import pytest
import yaml
from jsonschema import ValidationError
from openpyxl import load_workbook


SCRIPT = Path(__file__).parents[1] / "build_scenario.py"


def load_builder():
    spec = importlib.util.spec_from_file_location("build_scenario", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ford_pack():
    return {
        "slug": "ford-auto",
        "customer": {"name": "福特中国", "industry": "汽车", "locale": "zh-CN"},
        "course": {"code": "MS-4018", "purpose": "Demo"},
        "tenantDomain": "moneyyu.com",
        "roles": {
            "Admin": {"upn": "admin@moneyyu.com", "displayName": "Admin"},
            "Planner": {"upn": "AdeleV@moneyyu.com", "displayName": "Adele Vance"},
            "Sales": {"upn": "NestorW@moneyyu.com", "displayName": "Nestor Wilke"},
        },
        "teams": {
            "channels": [
                {
                    "channelName": "新车上市",
                    "channelDescription": "工作动态",
                    "messages": [
                        {
                            "fromRole": "Planner",
                            "dayOffset": -2,
                            "time": "09:00",
                            "bodyHtml": "<p>经销商库存复盘</p>",
                            "mentions": [],
                            "replies": [],
                        }
                    ],
                }
            ]
        },
        "emails": {
            "emailThreads": [
                {
                    "threadName": "复盘",
                    "emails": [
                        {
                            "action": "send",
                            "fromRole": "Planner",
                            "toRoles": ["Sales"],
                            "ccRoles": ["Admin"],
                            "subject": "20260929 经销商库存复盘",
                            "bodyHtml": "<p>请查看库存</p>",
                        },
                        {
                            "action": "reply",
                            "fromRole": "Sales",
                            "toRoles": ["Planner"],
                            "ccRoles": ["Admin"],
                            "subject": "Re: 20260929 经销商库存复盘",
                            "bodyHtml": "<p>收到</p>",
                        },
                    ],
                }
            ]
        },
        "workbooks": [
            {
                "filename": "经销商库存.xlsx",
                "sheets": [
                    {
                        "name": "库存",
                        "table": "DealerStock",
                        "headers": ["经销商", "现车", "月销", "库存天数"],
                        "rows": [["北京一店", 120, 30, None]],
                        "formulas": {"库存天数": '=IF(C{row}=0,0,B{row}/C{row}*30)'},
                        "chart": {"category": "经销商", "value": "现车"},
                    }
                ],
            }
        ],
    }


def write_pack(tmp_path, pack):
    path = tmp_path / "pack.yaml"
    path.write_text(yaml.safe_dump(pack, allow_unicode=True), encoding="utf-8")
    return path


def business_presentation():
    return {
        "teamDescription": "營運協作",
        "filesDirectory": "FILES",
        "workbookCreator": "營運管理",
        "workbookDescription": "營運追蹤",
        "notesSheetName": "資料口徑",
        "notesLines": ["資料截止：2026-09-28。", "未核准方案不視為已執行。"],
    }


def test_ford_outputs_only_declared_surfaces(tmp_path):
    builder = load_builder()
    output = tmp_path / "generated"
    builder.build_scenario(write_pack(tmp_path, ford_pack()), "20260929", output)
    assert {
        "config.json.example",
        "emails.json",
        "teams-messages.json",
        "files-manifest.json",
        "run.ps1",
        "README.md",
    } <= {p.name for p in output.iterdir()}
    assert not (output / "sharepoint-sites.json").exists()
    assert "Invoke-SeedUserProfiles" not in (output / "run.ps1").read_text(encoding="utf-8")
    assert "Invoke-SeedSharePoint" not in (output / "run.ps1").read_text(encoding="utf-8")
    config = json.loads((output / "config.json.example").read_text(encoding="utf-8"))
    assert config["teamDisplayName"] == "20260929-MS-4018"
    assert config["teamDescription"] == "MS-4018 dated training demo"
    assert config["filesSourceDir"] == "DEMO-FILE"
    runner = (output / "run.ps1").read_text(encoding="utf-8")
    assert "PreflightOnly" in runner
    assert '$preflight.FilesManifestPath = Join-Path $root "files-manifest.json"' in runner
    assert 'Invoke-UploadFiles.ps1") -ConfigPath $configPath -FilesManifestPath (Join-Path $root "files-manifest.json") -StrictScenario' in runner
    teams = json.loads((output / "teams-messages.json").read_text(encoding="utf-8"))
    assert teams["channels"][0]["messages"][0]["createdDateTime"] == "2026-09-27T09:00:00+08:00"
    book = load_workbook(output / "DEMO-FILE" / "经销商库存.xlsx")
    assert book["库存"]["D2"].value == "=IF(C2=0,0,B2/C2*30)"
    assert "DealerStock" in book["库存"].tables
    assert len(book["库存"]._charts) == 1
    assert book.properties.creator == "MS-4018 demo"
    assert book.properties.description == "Fictional training data, not customer-reported results."
    assert book["演示说明"]["A1"].value == "模拟教学数据，非客户官方业绩或已确认的召回信息。"
    assert book["演示说明"]["A2"].value == "来源：本地 Customer Pack；所有结论请根据数据表重新核对。"


@pytest.mark.parametrize("files_directory", ["FILES", "A" + "b" * 61 + "_9"])
def test_presentation_controls_business_outputs(tmp_path, files_directory):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = business_presentation()
    pack["presentation"]["filesDirectory"] = files_directory
    output = tmp_path / "business"
    builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    config = json.loads((output / "config.json.example").read_text(encoding="utf-8"))
    assert config["teamDescription"] == pack["presentation"]["teamDescription"]
    assert config["filesSourceDir"] == files_directory
    manifest = json.loads((output / "files-manifest.json").read_text(encoding="utf-8"))
    for item in manifest["files"]:
        workbook_path = output / config["filesSourceDir"] / item["localName"]
        book = load_workbook(workbook_path)
        assert book.properties.creator == pack["presentation"]["workbookCreator"]
        assert book.properties.description == pack["presentation"]["workbookDescription"]
        assert book["資料口徑"]["A1"].value == pack["presentation"]["notesLines"][0]
        assert book["資料口徑"]["A2"].value == pack["presentation"]["notesLines"][1]
        assert "演示说明" not in book.sheetnames
        assert book["库存"]["D2"].value == "=IF(C2=0,0,B2/C2*30)"
        assert "DealerStock" in book["库存"].tables
        assert len(book["库存"]._charts) == 1
    assert not (output / "DEMO-FILE").exists()
    assert (output / "run.ps1").read_text(encoding="utf-8") == builder.runner(ford_pack())


def test_make_workbook_accepts_optional_presentation():
    builder = load_builder()
    source = ford_pack()["workbooks"][0]
    presentation = business_presentation()
    presentation["notesSheetName"] = "N" * 31
    custom = builder.make_workbook(source, presentation)
    book = load_workbook(io.BytesIO(custom))
    assert book.sheetnames == ["库存", "N" * 31]
    assert book.properties.creator == presentation["workbookCreator"]
    assert book["N" * 31]["A2"].value == presentation["notesLines"][1]
    assert custom == builder.make_workbook(source, presentation)
    assert builder.make_workbook(source) == builder.make_workbook(source, None)


def test_presentation_directory_remains_consistent_with_source_archive(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = business_presentation()
    legacy = yaml.safe_load(
        (SCRIPT.parents[1] / "packs" / "ms4022-productsupport" / "pack.yaml").read_text(encoding="utf-8")
    )
    pack["sourceArchive"] = legacy["sourceArchive"]
    output = tmp_path / "business-with-archive"
    builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    config = json.loads((output / "config.json.example").read_text(encoding="utf-8"))
    assert config["filesSourceDir"] == "FILES"
    assert (output / config["filesSourceDir"] / pack["workbooks"][0]["filename"]).is_file()


def test_presentation_readme_requires_fingerprint_bound_approval(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = business_presentation()
    output = tmp_path / "approval-instructions"
    builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    readme = (output / "README.md").read_text(encoding="utf-8")
    for requirement in (
        "Status: offline; live writes are not authorized.",
        "explicit approval of the exact fingerprint",
        "approved manifest",
        "Immediately before any live write",
        "rehash",
        "compare it with the approved fingerprint",
        "executable code, data files, recipients, and targets",
        "GET-only preflight",
        "Stop on any mismatch",
    ):
        assert requirement in readme
    legacy_output = tmp_path / "legacy-instructions"
    builder.build_scenario(write_pack(tmp_path, ford_pack()), "20260929", legacy_output)
    legacy_readme = (
        "# MS-4018 ford-auto (20260929)\n\n"
        "Fictional demonstration content; customer names are narrative only. "
        "Only existing, enabled tenant accounts may be used. This seeder never creates users.\n\n"
        "Copy `config.json.example` to locally ignored `config.json`, provide app credentials, "
        "then run `pwsh -File .\\run.ps1 -PreflightOnly` before `pwsh -File .\\run.ps1`. "
        "Stop on any ambiguity; never delete, rename, or repair tenant resources by name. "
        "Outlook messages display execution date (not historical time).\n"
    )
    assert (legacy_output / "README.md").read_bytes() == legacy_readme.replace("\n", os.linesep).encode("utf-8")


@pytest.mark.parametrize(
    "field",
    ["teamDescription", "filesDirectory", "workbookCreator", "workbookDescription", "notesSheetName", "notesLines"],
)
def test_presentation_requires_every_field_before_output(tmp_path, field):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = business_presentation()
    del pack["presentation"][field]
    output = tmp_path / "incomplete"
    with pytest.raises(ValidationError):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


@pytest.mark.parametrize(
    "change",
    [
        *[
            {field: ""}
            for field in ("teamDescription", "filesDirectory", "workbookCreator", "workbookDescription", "notesSheetName")
        ],
        {"notesLines": []},
        {"notesLines": ["一行"]},
        {"notesLines": ["一", "二", "三"]},
        {"notesLines": ["", "二"]},
        {"notesLines": ["一", ""]},
        {"notesLines": ["一", 2]},
        {"notesSheetName": "N" * 32},
        {"filesDirectory": "A" * 65},
        {"filesDirectory": ".."},
        {"filesDirectory": "C:\\FILES"},
        {"filesDirectory": "parent\\FILES"},
        {"filesDirectory": "parent/FILES"},
        {"filesDirectory": "業務"},
        {"filesDirectory": "1FILES"},
        {"filesDirectory": "FILES."},
        {"extra": "not allowed"},
    ],
)
def test_invalid_presentation_schema_leaves_no_output(tmp_path, change):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = {**business_presentation(), **change}
    output = tmp_path / "invalid-presentation"
    with pytest.raises(ValidationError):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


@pytest.mark.parametrize(
    "files_directory",
    ["CON", "prn", "Aux", "nul", *[f"COM{i}" for i in range(1, 10)], *[f"lpt{i}" for i in range(1, 10)], "FILES\n"],
)
def test_unsafe_presentation_directory_rejected_before_output(tmp_path, files_directory):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = {**business_presentation(), "filesDirectory": files_directory}
    output = tmp_path / "reserved"
    with pytest.raises(ValueError, match="filesDirectory"):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


@pytest.mark.parametrize("invalid_character", list("[]\\/*?:"))
def test_invalid_notes_sheet_name_rejected_before_output(tmp_path, invalid_character):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = {**business_presentation(), "notesSheetName": f"口徑{invalid_character}"}
    output = tmp_path / "invalid-notes"
    with pytest.raises(ValueError, match="sheet name"):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


def test_notes_sheet_collision_in_later_workbook_rejected_before_output(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    pack["presentation"] = {**business_presentation(), "notesSheetName": "review"}
    pack["workbooks"].append(
        {
            "filename": "other.xlsx",
            "sheets": [{"name": "ReViEw", "table": "Other", "headers": ["數量"], "rows": [[1]]}],
        }
    )
    output = tmp_path / "colliding-notes"
    with pytest.raises(ValueError, match="sheet name"):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


def test_deterministic_workbook_bytes(tmp_path):
    builder = load_builder()
    pack = write_pack(tmp_path, ford_pack())
    builder.build_scenario(pack, "20260929", tmp_path / "a")
    time.sleep(1.1)
    builder.build_scenario(pack, "20260929", tmp_path / "b")
    assert (tmp_path / "a" / "DEMO-FILE" / "经销商库存.xlsx").read_bytes() == (
        tmp_path / "b" / "DEMO-FILE" / "经销商库存.xlsx"
    ).read_bytes()


@pytest.mark.parametrize(
    "change",
    [
        lambda p: p["roles"]["Sales"].update(upn="another@example.com"),
        lambda p: p["emails"]["emailThreads"][0]["emails"][1].update(fromRole="Planner"),
        lambda p: p["emails"]["emailThreads"][0]["emails"][0].update(ccRoles=[]),
        lambda p: p["teams"]["channels"][0].update(channelName="新车/上市"),
        lambda p: p["course"].update(purpose="福特 Demo"),
        lambda p: p["emails"]["emailThreads"][0]["emails"][0].update(subject="库存复盘"),
        lambda p: p["roles"].update(New={"createUser": True}),
    ],
)
def test_invalid_pack_fails_without_output(tmp_path, change):
    builder = load_builder()
    pack = ford_pack()
    change(pack)
    output = tmp_path / "generated"
    with pytest.raises((ValueError, ValidationError)):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


def test_sharepoint_only_outputs_and_runner(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    del pack["teams"]
    del pack["emails"]
    del pack["workbooks"]
    pack["sharepoint"] = {
        "sites": [
            {
                "alias": "ms4022-productsupport-{{DATE}}",
                "displayName": "MS-4022 - Product support - {{DATE}}",
                "owners": ["Admin"],
                "members": ["Sales"],
                "documents": [],
                "lists": [],
                "documentLibrary": "Products",
            }
        ]
    }
    output = tmp_path / "generated"
    builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert (output / "sharepoint-sites.json").exists()
    assert not (output / "teams-messages.json").exists()
    assert not (output / "emails.json").exists()
    assert not (output / "files-manifest.json").exists()
    runner = (output / "run.ps1").read_text(encoding="utf-8")
    assert "Invoke-SeedSharePoint" in runner
    assert "Invoke-SeedEmails" not in runner
    assert "Invoke-UploadFiles" not in runner


def test_bad_generation_rule_cannot_leave_partial_scenario(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    sheet = pack["workbooks"][0]["sheets"][0]
    sheet["headers"] = ["经销商", "月份", "销量"]
    sheet.pop("rows")
    sheet.pop("formulas")
    sheet["generate"] = {
        "seed": 42,
        "dimensions": ["北京"],
        "periods": ["9月"],
        "min": 10,
        "max": 50,
        "overrides": [{"dimension": "上海", "period": "9月", "value": 100}],
    }
    output = tmp_path / "invalid"
    with pytest.raises(ValueError, match="Override"):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()


def test_ford_pack_has_consistent_simulated_facts():
    builder = load_builder()
    pack = yaml.safe_load(
        (SCRIPT.parents[1] / "packs" / "ms4018-ford-auto" / "pack.yaml").read_text(
            encoding="utf-8"
        )
    )
    builder.validate_pack(pack, "20260929")
    assert len(pack["teams"]["channels"]) == 5
    assert len(pack["emails"]["emailThreads"]) == 5
    assert len(pack["workbooks"]) == 5
    sheets = {
        book["filename"]: book["sheets"] for book in pack["workbooks"]
    }
    assert sum(r[2] for r in sheets["新车销售追踪.xlsx"][0]["rows"]) == 860
    assert sum(r[3] for r in sheets["新车销售追踪.xlsx"][0]["rows"]) == 960
    monthly = sheets["新车销售追踪.xlsx"][0]["rows"]
    regional = sheets["新车销售追踪.xlsx"][1]["rows"]
    for month, _, actual, target, _ in monthly:
        assert sum(r[2] for r in regional if r[0] == month) == actual
        assert sum(r[3] for r in regional if r[0] == month) == target
    assert sheets["经销商库存.xlsx"][0]["rows"][0][:3] == ["上海一店", 240, 30]
    assert sheets["零部件品质追踪.xlsx"][0]["rows"][0][2:4] == [1800, 1470]
    assert sheets["零部件品质追踪.xlsx"][1]["rows"][0][2:4] == [600, 36]
    assert sheets["售后NPS.xlsx"][0]["rows"][0][1:4] == [62, 31, 100]
    assert sheets["工厂KPI.xlsx"][0]["rows"][0][1:3] == [1000, 924]


def test_ms4022_archive_requires_all_documents_before_graph_write(tmp_path):
    builder = load_builder()
    pack = yaml.safe_load(
        (SCRIPT.parents[1] / "packs" / "ms4022-productsupport" / "pack.yaml").read_text(
            encoding="utf-8"
        )
    )
    output = tmp_path / "ms4022"
    builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    runner = (output / "run.ps1").read_text(encoding="utf-8")
    assert "-ne 9" in runner
    assert runner.index("-ne 9") < runner.index("Invoke-SeedSharePoint")
    assert "GetRelativePath($source, $_.FullName)" in runner
    assert "$config.filesSourceDir" in runner
    assert "[System.IO.Path]::IsPathRooted($config.filesSourceDir)" in runner
    assert "StartsWith($rootFull" in runner
    assert "Join-Path (Split-Path $source -Parent) \"Products.zip\"" in runner


def test_bad_table_name_is_rejected_before_scenario_creation(tmp_path):
    builder = load_builder()
    pack = ford_pack()
    pack["workbooks"][0]["sheets"][0]["table"] = "Invalid Table"
    output = tmp_path / "invalid-table"
    with pytest.raises(ValueError, match="table"):
        builder.build_scenario(write_pack(tmp_path, pack), "20260929", output)
    assert not output.exists()
