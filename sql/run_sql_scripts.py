"""
Runs the four SQL scripts against a TEMPORARY COPY of the raw database (data/raw is never modified),
prints every query result and exports the summary tables used by Python and Excel to data/cleaned/.

Usage (from the project root):  python sql/run_sql_scripts.py
"""
import shutil, sqlite3, tempfile, os, sys
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw", "marketing-campaigns-v1.0.0.sqlite")
OUT = os.path.join(ROOT, "data", "cleaned")
SCRIPTS = ["01_database_exploration.sql", "02_data_cleaning.sql", "03_marketing_kpis.sql", "04_business_analysis.sql"]
EXPORTS = {  # summary tables exported for Python / Excel
    "sql_campaign_kpis.csv": "SELECT * FROM campaign_kpis ORDER BY campaign_id",
    "sql_channel_kpis.csv": "SELECT * FROM channel_kpis ORDER BY roas DESC",
    "sql_objective_kpis.csv": "SELECT * FROM objective_kpis ORDER BY roas DESC",
    "sql_monthly_kpis.csv": "SELECT * FROM monthly_kpis ORDER BY month",
    "sql_campaign_tiers.csv": "SELECT * FROM campaign_tiers ORDER BY score DESC",
}

def statements(text):
    """Split a script into (title, statement) pairs using sqlite3.complete_statement."""
    buf, title, out = "", "", []
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if not buf and not s:
            continue
        if not buf and s.startswith("--"):
            if s.lower().startswith(("-- query", "-- check")):
                title = s[2:].strip()
            continue
        buf += line
        if sqlite3.complete_statement(buf):
            if buf.strip().rstrip(";").strip():
                out.append((title, buf.strip()))
            buf = ""
    return out

def main(verbose=True):
    tmp = os.path.join(tempfile.mkdtemp(), "working_copy.sqlite")
    shutil.copy(RAW, tmp)
    con = sqlite3.connect(tmp)
    pd.set_option("display.width", 220); pd.set_option("display.max_columns", 30)
    for script in SCRIPTS:
        print("=" * 100, "\n", script, "\n", "=" * 100)
        for title, stmt in statements(open(os.path.join(ROOT, "sql", script), encoding="utf-8").read()):
            if stmt.upper().startswith(("SELECT", "WITH")):
                df = pd.read_sql(stmt, con)
                if verbose:
                    print(f"\n-- {title}\n{df.head(20).to_string(index=False)}")
            else:
                con.execute(stmt)
    os.makedirs(OUT, exist_ok=True)
    for fname, q in EXPORTS.items():
        pd.read_sql(q, con).to_csv(os.path.join(OUT, fname), index=False)
        print("exported", fname)
    con.close()
    shutil.rmtree(os.path.dirname(tmp))

if __name__ == "__main__":
    main(verbose="--quiet" not in sys.argv)
