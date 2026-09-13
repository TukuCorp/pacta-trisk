from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from dashboard.lib import loaders


# Wave 4 PHASE-06. Before this phase the PCAF inventory, the sector target
# registry and the SLL shortlist reached the dashboard only as static HTML, so
# there was nothing to load and nothing to test.


@pytest.fixture()
def analytics_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    d = tmp_path / "analytics"
    d.mkdir()
    monkeypatch.setenv("PACTATRISK_SNAPSHOT_DIR", str(tmp_path))
    # The app resolves every table path from the Artifact catalog the snapshot
    # step writes (ADR-0001), so a fixture snapshot needs its own catalog.
    (tmp_path / "artifact_catalog.json").write_text(
        json.dumps({
            "schema_version": 1,
            "bank_slug": "test-bank",
            "sectors": [],
            "artifacts": [
                {"key": key, "group": "analytics", "scope": "engagement", "sector": None,
                 "producer": "financed_emissions", "kind": "csv",
                 "snapshot_path": f"analytics/{key}.csv"}
                for key in loaders.ANALYTICS_TABLE_KEYS
            ],
        }),
        encoding="utf-8",
    )
    # load_csv is memoized by streamlit's cache; clear it between cases so a
    # path reused across tests does not serve a stale frame.
    loaders.load_csv.clear()
    # Same for the artifact catalog, which is memoized on its resolved path.
    loaders._load_artifact_catalog_cached.clear()
    return d


def _write(d: Path, name: str, frame: pd.DataFrame) -> None:
    frame.to_csv(d / name, index=False)


def test_loads_every_table_that_is_present(analytics_dir: Path) -> None:
    _write(analytics_dir, "financed_emissions.csv",
           pd.DataFrame({"name_abcd": ["A"], "financed_emissions_tco2e": [1.0],
                         "data_source": ["mcb-demo"]}))
    _write(analytics_dir, "data_quality_summary.csv",
           pd.DataFrame({"data_quality_score": [4], "n_borrowers": [1],
                         "financed_emissions_tco2e": [1.0], "share_of_total": [1.0]}))
    _write(analytics_dir, "target_registry.csv",
           pd.DataFrame({"sector": ["power"], "target_year": [2030]}))
    _write(analytics_dir, "sll_readiness.csv",
           pd.DataFrame({"name_abcd": ["A"], "readiness": [0.5]}))

    tables = loaders.load_analytics_tables()

    assert set(tables) == {
        "financed_emissions", "data_quality_summary", "target_registry", "sll_readiness"
    }
    assert all(isinstance(t, pd.DataFrame) and not t.empty for t in tables.values())


def test_omits_absent_tables_without_raising(analytics_dir: Path) -> None:
    _write(analytics_dir, "financed_emissions.csv",
           pd.DataFrame({"name_abcd": ["A"], "financed_emissions_tco2e": [1.0]}))

    tables = loaders.load_analytics_tables()

    assert set(tables) == {"financed_emissions"}


def test_missing_analytics_directory_yields_empty_dict(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # An older snapshot predates analytics/ entirely; the app must degrade, not
    # crash, exactly as report_catalog() does for a missing sidecar.
    monkeypatch.setenv("PACTATRISK_SNAPSHOT_DIR", str(tmp_path / "does_not_exist"))
    loaders.load_csv.clear()
    loaders._load_artifact_catalog_cached.clear()

    assert loaders.load_analytics_tables() == {}


def test_analytics_path_resolves_under_the_analytics_dir(analytics_dir: Path) -> None:
    assert loaders.analytics_path("financed_emissions.csv").parent == analytics_dir


def test_published_inventory_carries_the_publishing_bank_slug() -> None:
    # The dashboard-side echo of the Wave 4 PHASE-03 provenance fix: the public
    # snapshot is the mcb-demo engagement, so its inventory must say so.
    path = loaders.snapshot_root() / "analytics" / "financed_emissions.csv"
    if not path.exists():
        pytest.skip("analytics snapshot not present in this checkout")
    frame = pd.read_csv(path)
    if "data_source" not in frame.columns:
        pytest.skip("inventory predates the data_source column")
    assert set(frame["data_source"].dropna().unique()) <= {"mcb-demo"}


def test_financed_emissions_page_states_the_data_is_synthetic() -> None:
    page = Path(__file__).resolve().parents[1] / "pages" / "8_Financed_Emissions.py"
    assert page.exists()
    assert "Synthetic" in page.read_text(encoding="utf-8")
