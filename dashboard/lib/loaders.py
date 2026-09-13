from __future__ import annotations

import os

import json
from pathlib import Path

import pandas as pd
import streamlit as st


ROOT = Path(__file__).resolve().parents[1]


def snapshot_root() -> Path:
    """The snapshot directory the app reads (Wave 5 PHASE-06).

    From `PACTATRISK_SNAPSHOT_DIR` when set, otherwise the frozen public
    snapshot `dashboard/data`. A client engagement is a directory, not a
    repository fork.
    """
    return Path(os.environ.get("PACTATRISK_SNAPSHOT_DIR", str(ROOT / "data"))).resolve()


def pacta_dir() -> Path:
    return snapshot_root() / "pacta"


def trisk_dir() -> Path:
    return snapshot_root() / "trisk"


def reports_dir() -> Path:
    return snapshot_root() / "reports"


def analytics_dir() -> Path:
    return snapshot_root() / "analytics"


def pipeline_manifest_path() -> Path:
    return snapshot_root() / "pipeline_manifest.json"


def artifact_catalog_path() -> Path:
    """The machine-readable Artifact catalog written by the snapshot step."""
    return snapshot_root() / "artifact_catalog.json"


def load_pipeline_manifest() -> dict | None:
    """Read the pipeline refresh manifest, or None if it hasn't been generated yet."""
    manifest_path = pipeline_manifest_path()
    if not manifest_path.exists():
        return None
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


# Every cached loader takes its path as an argument (never closes over a
# module-level snapshot directory), so switching PACTATRISK_SNAPSHOT_DIR
# mid-session serves the new snapshot instead of a stale memoized frame.


@st.cache_data(show_spinner=False)
def load_csv(path: str | Path) -> pd.DataFrame:
    return pd.read_csv(path)


@st.cache_data(show_spinner=False)
def load_markdown_text(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8")


@st.cache_data(show_spinner=False)
def load_bytes(path: str | Path) -> bytes:
    return Path(path).read_bytes()


@st.cache_data(show_spinner=False)
def _load_artifact_catalog_cached(path: str) -> dict:
    resolved = Path(path)
    if not resolved.exists():
        raise FileNotFoundError(
            f"{resolved} not found: regenerate the snapshot with "
            "Rscript scripts/refresh_dashboard_data.R --config <engagement config>"
        )
    return json.loads(resolved.read_text(encoding="utf-8"))


def load_artifact_catalog(path: str | Path | None = None) -> dict:
    """The Artifact catalog `scripts/refresh_dashboard_data.R` writes into the
    snapshot from `R/artifact_catalog.R` (ADR-0001).

    Every table path the app reads is resolved from this file instead of being
    spelled here. A snapshot generated before the catalog existed has no
    `artifact_catalog.json`; the error names the exact regeneration command.
    """
    resolved = Path(path) if path is not None else artifact_catalog_path()
    return _load_artifact_catalog_cached(str(resolved))


def artifact_snapshot_path(key: str, sector: str | None = None) -> Path:
    """Absolute path of one catalogued Snapshot file.

    `sector` selects the row for a sector-scoped Artifact; engagement-scoped
    Artifacts have no sector, so passing one is a lookup miss, not a fallback.
    """
    for row in load_artifact_catalog().get("artifacts", []):
        if row.get("key") != key or row.get("sector") != sector:
            continue
        return snapshot_root() / row["snapshot_path"]
    raise KeyError(
        f"artifact '{key}'"
        + (f" sector '{sector}'" if sector is not None else "")
        + " is not in artifact_catalog.json"
    )


def pacta_path(name: str) -> Path:
    return pacta_dir() / name


def analytics_path(name: str) -> Path:
    return analytics_dir() / name


# The analytics keys the snapshot may carry; each is resolved from the Artifact
# catalog, so no filename is spelled here.
ANALYTICS_TABLE_KEYS = (
    "financed_emissions",
    "data_quality_summary",
    "target_registry",
    "sll_readiness",
)


def load_analytics_tables() -> dict[str, pd.DataFrame]:
    """The Wave 3 analytics (PCAF inventory, target registry, SLL shortlist) as
    data rather than rendered HTML.

    A table that is absent is omitted from the result rather than raising: an
    engagement may not have run financed emissions, targets or the SLL screen,
    and an older snapshot predates the analytics/ directory entirely.
    """
    tables: dict[str, pd.DataFrame] = {}
    for key in ANALYTICS_TABLE_KEYS:
        try:
            path = artifact_snapshot_path(key)
        except (KeyError, FileNotFoundError, OSError):
            continue
        if not path.exists():
            continue
        try:
            tables[key] = load_csv(path)
        except (OSError, ValueError, pd.errors.ParserError):
            continue
    return tables


# Page-facing key -> catalog key (DEC-002). The PACTA keys and their page names
# are identical, so this list is one-to-one.
PACTA_TABLE_KEYS = (
    "matches",
    "ms_company",
    "ms_portfolio",
    "sda_portfolio",
    "ms_alignment",
    "sda_alignment",
)


def load_pacta_alignment_tables() -> dict[str, pd.DataFrame]:
    return {key: load_csv(artifact_snapshot_path(key)) for key in PACTA_TABLE_KEYS}


def load_trisk_tables() -> dict[str, pd.DataFrame]:
    manifest = load_csv(artifact_snapshot_path("trisk_manifest"))
    default_sector = manifest.iloc[0]["sector"]
    return {
        "manifest": manifest,
        "default_sector": pd.DataFrame({"sector": [default_sector]}),
        **load_trisk_sector_tables(default_sector),
    }


# Page-facing key -> catalog key (DEC-002). Two page contracts differ from the
# catalog's semantic keys; the rest are one-to-one. Order is the order the page
# has always received.
TRISK_SECTOR_TABLE_KEYS = {
    "assets": "assets",
    "company_summary": "company_summary",
    "company_trajectories_latest": "company_trajectories",
    "npv_results": "npv_results",
    "pd_results": "pd_results",
    "pd_summary": "pd_summary",
    "financial_features": "financial_features",
    "carbon_price": "carbon_price",
    "run_catalog": "run_catalog",
    "scenarios": "scenarios",
    "sensitivity_results": "sensitivity_results",
    "sensitivity_summary": "sensitivity_summary",
    "combined": "top_borrowers",
}


def load_trisk_sector_tables(sector: str) -> dict[str, pd.DataFrame]:
    return {
        page_key: load_csv(artifact_snapshot_path(catalog_key, sector))
        for page_key, catalog_key in TRISK_SECTOR_TABLE_KEYS.items()
    }


@st.cache_data(show_spinner=False)
def load_parquet(path: str | Path) -> pd.DataFrame:
    return pd.read_parquet(path)


def load_trisk_grid(sector: str) -> dict[str, pd.DataFrame]:
    return {
        "scenarios": load_csv(artifact_snapshot_path("grid_scenarios", sector)),
        "borrower_results": load_parquet(artifact_snapshot_path("grid_borrower_results", sector)),
    }


def list_report_files() -> list[Path]:
    return sorted(reports_dir().glob("*.html"))


def _load_report_catalog_sidecar() -> dict[str, dict[str, str]]:
    """Read the report_catalog.json sidecar copied into the snapshot by
    scripts/refresh_dashboard_data.R (Wave 3 PHASE-02). Returns {} if the
    sidecar is absent (e.g. an old snapshot predating this phase) or
    unreadable -- report_catalog() below degrades every file to an
    uncatalogued entry rather than raising.
    """
    sidecar_path = reports_dir() / "report_catalog.json"
    if not sidecar_path.exists():
        return {}
    try:
        import json

        return json.loads(sidecar_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _artifact_date(path: Path, fallback: str = "") -> str:
    """Displayed date for a published artifact (Wave 5 PHASE-04): the file's
    own modification date formatted YYYY-MM-DD, falling back to the catalog
    string when stat() raises."""
    import datetime

    try:
        return datetime.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
    except OSError:
        return fallback


def report_catalog() -> list[dict[str, str | Path]]:
    """Every HTML file actually present in the reports snapshot, with
    metadata from report_catalog.json when available. A published file with
    no catalog entry is never silently dropped (Wave 3 PHASE-02, N-008) --
    it gets a filename-derived title and an explicit "no summary" marker
    instead. The displayed date comes from the artifact file itself, not
    the catalog's hand-typed string (Wave 5 PHASE-04).
    """
    catalog = _load_report_catalog_sidecar()
    rows: list[dict[str, str | Path]] = []
    for path in list_report_files():
        meta = catalog.get(path.name)
        if meta:
            rows.append({
                "path": path,
                "title": meta.get("title", path.stem),
                "date": _artifact_date(path, meta.get("date", "")),
                "summary": meta.get("summary", "No summary available."),
                "category": meta.get("category", "uncatalogued"),
            })
        else:
            rows.append({
                "path": path,
                "title": path.stem,
                "date": _artifact_date(path),
                "summary": "No summary available.",
                "category": "uncatalogued",
            })
    return rows
