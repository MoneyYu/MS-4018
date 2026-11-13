import json
import re
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile

import pytest
import yaml
from openpyxl import load_workbook

from test_build_scenario import load_builder


PACK = Path(__file__).parents[2] / "packs" / "ms4018-quanta-operations" / "pack.yaml"
FORBIDDEN = re.compile(
    r"\b(?:demo|demonstration|sample|mock|fixture|training|workshop|test)\b"
    r"|演示|示範|模擬|模拟|測試|测试|教學|教学|範例|范例",
    re.IGNORECASE,
)


def read_pack():
    assert PACK.is_file(), "The Quanta business pack must be provided"
    return yaml.safe_load(PACK.read_text(encoding="utf-8"))


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


@pytest.fixture
def generated(tmp_path):
    builder = load_builder()
    pack = read_pack()
    output = tmp_path / "quanta"
    builder.build_scenario(PACK, "20261112", output)
    return builder, pack, output


def test_quanta_cross_surface_business_facts():
    pack = read_pack()
    sheets = {s["table"]: s for b in pack["workbooks"] for s in b["sheets"]}
    tasks = sheets["NpiMilestones"]["rows"]
    done = sum(row[6] == "已完成" for row in tasks)
    material = sheets["MaterialDelivery"]["rows"][0]
    quality = sheets["QualityLots"]["rows"][0]
    production = next(
        r for r in sheets["ProductionYield"]["rows"]
        if r[:2] == ["2026-11-11", "製造一區"]
    )
    shipment = sheets["ShipmentCommitments"]["rows"][0]
    facts = [
        [f"{done}/{len(tasks)}", f"{done / len(tasks) * 100:g}%"],
        [f"{material[3]}/{material[2]}", f"缺口 {material[2] - material[3]} 件"],
        [f"{quality[3]}/{quality[2]}", f"{quality[3] / quality[2] * 100:g}%"],
        [f"{production[3]}/{production[2]}",
         f"{production[3] / production[2] * 100:g}%",
         f"{production[5] - production[3] / production[2] * 100:.1f} 個百分點"],
        [f"{shipment[3]}/{shipment[2]}", f"未交 {shipment[2] - shipment[3]} 台",
         f"{shipment[3] / shipment[2] * 100:g}%"],
    ]
    assert done == 21 and len(tasks) == 24
    assert {r[6] for r in tasks if r[6] != "已完成"} == {"待料", "待驗證", "待核准"}
    assert material[2:4] == [1200, 1050]
    assert quality[2:4] == [400, 12]
    assert production[2:4] == [1000, 962]
    assert shipment[2:4] == [800, 720]
    for channel, thread, claims in zip(
        pack["teams"]["channels"], pack["emails"]["emailThreads"], facts, strict=True
    ):
        for corpus in (channel, thread):
            text = " ".join(strings(corpus))
            for claim in claims:
                assert claim in text, f"Missing derived fact {claim}: {text}"
    assert "不能直接歸因" in " ".join(strings(pack["emails"]))
    assert "待核准" in " ".join(strings(pack["teams"]["channels"][1]))


def test_quanta_timeline_recipients_and_selected_surfaces(generated):
    builder, pack, output = generated
    builder.validate_pack(pack, "20261112")
    channels = json.loads((output / "teams-messages.json").read_text(encoding="utf-8"))["channels"]
    assert len(channels) == len(pack["workbooks"]) == len(pack["emails"]["emailThreads"]) == 5
    assert sum(len(c["messages"]) for c in channels) == 10
    assert sum(len(m["replies"]) for c in channels for m in c["messages"]) == 10
    for source, channel in zip(pack["teams"]["channels"], channels, strict=True):
        for original, message in zip(source["messages"], channel["messages"], strict=True):
            assert original["dayOffset"] in {-6, -1}
            parent = datetime.fromisoformat(message["createdDateTime"])
            assert parent.date().isoformat() <= "2026-11-11"
            for reply in message["replies"]:
                assert parent < datetime.fromisoformat(reply["createdDateTime"])
    assert sum(len(t["emails"]) for t in pack["emails"]["emailThreads"]) == 15
    for thread in pack["emails"]["emailThreads"]:
        for previous, reply in zip(thread["emails"], thread["emails"][1:]):
            assert reply["fromRole"] in previous["toRoles"] + previous["ccRoles"]
        assert all("Admin" in email["ccRoles"] for email in thread["emails"])
    runner = (output / "run.ps1").read_text(encoding="utf-8")
    for forbidden_phase in ("SeedUserProfiles", "SeedCalendar", "SeedMeetingChats", "SeedSharePoint"):
        assert forbidden_phase not in runner
    assert not (output / "sharepoint-sites.json").exists()
    config = json.loads((output / "config.json.example").read_text(encoding="utf-8"))
    assert config["teamDisplayName"] == "20261112-MS-4018"
    assert config["filesSourceDir"] == "FILES"
    assert config["adminUpn"] == config["demoUserUpn"] == config["roles"]["Admin"]["upn"]
    assert all(v.startswith("<") for k, v in config.items() if k in {"tenantId", "clientId", "clientSecret"})


def test_quanta_business_output_has_no_demonstration_labels(generated):
    _, pack, output = generated
    config = json.loads((output / "config.json.example").read_text(encoding="utf-8"))
    manifest = json.loads((output / "files-manifest.json").read_text(encoding="utf-8"))
    texts = list(strings([pack["teams"], pack["emails"], pack["workbooks"], pack["presentation"]]))
    texts.extend([config["teamDisplayName"], config["teamDescription"], manifest["targetFolder"]])
    for path in (output / "FILES").glob("*.xlsx"):
        texts.append(path.name)
        book = load_workbook(path)
        texts.extend(book.sheetnames)
        texts.extend(str(v) for v in vars(book.properties).values() if v is not None)
        for sheet in book:
            texts.extend(str(c.value) for row in sheet for c in row if isinstance(c.value, str))
        with ZipFile(path) as archive:
            texts.extend(archive.read(n).decode("utf-8") for n in archive.namelist() if n.endswith(".xml"))
    for text in texts:
        assert not FORBIDDEN.search(text), f"Business label leaked: {text}"


def test_quanta_workbooks_formulas_tables_and_dimensions(generated):
    _, pack, output = generated
    for definition in pack["workbooks"]:
        book = load_workbook(output / "FILES" / definition["filename"])
        assert len(book.sheetnames) == len(definition["sheets"]) + 1
        assert book["資料口徑"]["A1"].value.startswith("資料截止：2026-11-11")
        for source in definition["sheets"]:
            sheet = book[source["name"]]
            assert list(next(sheet.values)) == source["headers"]
            assert sheet.max_row == len(source["rows"]) + 1
            assert sheet.max_column == len(source["headers"])
            assert source["table"] in sheet.tables
            assert sheet.freeze_panes == "A2"
            for header, formula in source.get("formulas", {}).items():
                column = source["headers"].index(header) + 1
                assert sheet.cell(2, column).value == formula.replace("{row}", "2")
            if source.get("chart"):
                assert len(sheet._charts) == 1
        assert any(s.get("formulas") for s in definition["sheets"])
        assert any(s.get("chart") for s in definition["sheets"])
    for table in ("MaterialDelivery", "QualityLots", "ProductionYield", "ShipmentCommitments"):
        sheet = next(s for b in pack["workbooks"] for s in b["sheets"] if s["table"] == table)
        for row in sheet["rows"]:
            assert 0 <= row[3] <= row[2] and row[2] > 0


def test_quanta_regeneration_is_deterministic(generated, tmp_path):
    builder, pack, output = generated
    second = tmp_path / "second"
    builder.build_scenario(PACK, "20261112", second)
    for book in pack["workbooks"]:
        assert (output / "FILES" / book["filename"]).read_bytes() == (
            second / "FILES" / book["filename"]
        ).read_bytes()


def test_quanta_does_not_overwrite_existing_scenario(generated):
    builder, _, output = generated
    before = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
    with pytest.raises(FileExistsError):
        builder.build_scenario(PACK, "20261112", output)
    assert before == {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
