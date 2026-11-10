"""Shared helpers for the Veltrix report notebooks.

Every notebook in this folder starts with:
    import vx
    vx.connect()            # asks for the PostgreSQL password (never typed into a cell)
and then uses vx.Q("SELECT ...") to read the database into pandas.

Connection defaults: localhost:5432, user postgres, database veltrix (tries Veltrix too).
Change them without editing code by setting environment variables before starting Jupyter:
    VELTRIX_PG_HOST, VELTRIX_PG_PORT, VELTRIX_PG_USER, VELTRIX_PG_DB
"""
import getpass
import os
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.exc import OperationalError

# ------------------------------------------------------------------ paths
ROOT = Path(__file__).resolve().parent.parent          # ...\Project_veltrix\Marc
REPORTS = ROOT / "reports"
ANSWER_KEY = Path(os.environ.get(
    "VELTRIX_ANSWER_KEY",
    ROOT / "restricted" / "answer_key" / "veltrix_medium" / "_answer_key_customer_persona.parquet"))
DATA_END = pd.Timestamp("2026-09-30")


def out_dir(name):
    """reports/<name>/ (and its charts/ subfolder), created if missing."""
    d = REPORTS / name
    (d / "charts").mkdir(parents=True, exist_ok=True)
    return d


# ------------------------------------------------------------------ database
ENGINE = None


def connect(dbname=None):
    """Connect to PostgreSQL. The password is asked for with getpass, so it never sits in the notebook."""
    global ENGINE
    host = os.environ.get("VELTRIX_PG_HOST", "localhost")
    port = int(os.environ.get("VELTRIX_PG_PORT", "5432"))
    user = os.environ.get("VELTRIX_PG_USER", "postgres")
    pw = os.environ.get("VELTRIX_PG_PASSWORD") or getpass.getpass(f"PostgreSQL password for {user}@{host}: ")
    names = [dbname] if dbname else list(dict.fromkeys([os.environ.get("VELTRIX_PG_DB", "veltrix"), "veltrix", "Veltrix"]))
    last = None
    for n in names:
        try:
            eng = create_engine(URL.create("postgresql+psycopg2", username=user, password=pw, host=host, port=port, database=n))
            with eng.connect() as c:
                c.execute(text("SELECT 1"))
            ENGINE = eng
            print(f"Connected to database '{n}' on {host}:{port} as {user}")
            return eng
        except OperationalError as e:
            last = e
    raise last


def Q(sql, **params):
    """Run a SELECT and return a DataFrame."""
    with ENGINE.connect() as c:
        return pd.read_sql(text(sql), c, params=params)


def V(sql, **params):
    """Run a SELECT that returns one value."""
    with ENGINE.connect() as c:
        return c.execute(text(sql), params).scalar()


def run(sql, **params):
    """Run a statement that changes the database (CREATE, INSERT, UPDATE) and commit it."""
    with ENGINE.begin() as c:
        c.execute(text(sql), params)


def exists(relation):
    """True if a table or view such as 'clean.segment_tiers' exists."""
    return V("SELECT to_regclass(:r) IS NOT NULL", r=relation)


def segment_model():
    """The segmentation the dashboard currently shows (clean.segment_in_use)."""
    return V("SELECT model_version FROM clean.segment_in_use") if exists("clean.segment_in_use") else None


# ------------------------------------------------------------------ chart style
NAVY, ORANGE, GREY = "#1F4E79", "#E8702A", "#9BA7B4"            # Veltrix dashboard colours
INK, INK2, MUTED, GRID, SURFACE = "#1A1A1A", "#444444", "#7A7A7A", "#E3E5E8", "#FFFFFF"
# Categorical order for segments (colour-blind checked); always assigned in this order
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]


def style():
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 9.5, "axes.edgecolor": "#C9CDD2", "axes.labelcolor": INK2,
        "xtick.color": INK2, "ytick.color": INK2, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6,
        "axes.spines.top": False, "axes.spines.right": False, "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE, "axes.axisbelow": True, "legend.fontsize": 8.5,
        "legend.frameon": False,
    })


def finish(fig, ax, title, subtitle="", path=None, note=None, xlabel=None, ylabel=None):
    """Title states the finding; subtitle says what is plotted. Saves to path (PNG) and shows the chart."""
    fig.suptitle(title, x=0.01, ha="left", fontsize=12, fontweight="bold", color=INK, y=0.995)
    if subtitle:
        ax.set_title(subtitle, loc="left", fontsize=9, color=INK2, pad=8)
    if xlabel is not None:
        ax.set_xlabel(xlabel)
    if ylabel is not None:
        ax.set_ylabel(ylabel)
    if note:
        fig.text(0.01, 0.005, note, fontsize=7.5, color=MUTED, ha="left", va="bottom")
    fig.tight_layout(rect=(0, 0.035 if note else 0, 1, 0.95))
    if path:
        fig.savefig(path, dpi=200)
    plt.show()
    plt.close(fig)
    return path


def barh_labels(ax, bars, fmt="{:,.0f}", pad=3, color=INK2, size=8.5):
    for b in bars:
        w = b.get_width()
        ax.annotate(fmt.format(w), (w, b.get_y() + b.get_height() / 2), xytext=(pad, 0),
                    textcoords="offset points", va="center", fontsize=size, color=color)


def bar_labels(ax, bars, fmt="{:,.0f}", pad=3, color=INK2, size=8.5):
    for b in bars:
        h = b.get_height()
        ax.annotate(fmt.format(h), (b.get_x() + b.get_width() / 2, h), xytext=(0, pad),
                    textcoords="offset points", ha="center", fontsize=size, color=color)


# ------------------------------------------------------------------ number formats
def n(x):
    return f"{x:,.0f}"


def pct(x, d=1):
    return f"{x:.{d}f}%"


def gbp(x):
    if abs(x) >= 1e9:
        return f"£{x / 1e9:,.2f}bn"
    if abs(x) >= 1e6:
        return f"£{x / 1e6:,.1f}m"
    if abs(x) >= 1e3:
        return f"£{x / 1e3:,.0f}k"
    return f"£{x:,.0f}"


# ------------------------------------------------------------------ Word reports (python-docx)
from docx import Document                              # noqa: E402
from docx.enum.section import WD_ORIENT                # noqa: E402
from docx.enum.table import WD_TABLE_ALIGNMENT        # noqa: E402
from docx.enum.text import WD_ALIGN_PARAGRAPH         # noqa: E402
from docx.oxml import OxmlElement                     # noqa: E402
from docx.oxml.ns import qn                           # noqa: E402
from docx.shared import Cm, Pt, RGBColor              # noqa: E402

_NAVY = RGBColor(0x1F, 0x4E, 0x79)
_GREY = RGBColor(0x55, 0x55, 0x55)


def _shade(cell, hex_fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    tcPr.append(shd)


def _field(run, instr):
    for tag, txt in (("begin", None), (None, instr), ("end", None)):
        if tag:
            el = OxmlElement("w:fldChar")
            el.set(qn("w:fldCharType"), tag)
        else:
            el = OxmlElement("w:instrText")
            el.set(qn("xml:space"), "preserve")
            el.text = txt
        run._r.append(el)


class Report:
    """A small wrapper around python-docx with the Veltrix house style.

    r = vx.Report("Data quality report", "Veltrix segmentation · Phase 1")
    r.h1("Summary"); r.p("Text with **bold** parts"); r.bullets([...]); r.table(df); r.image(png, "caption")
    r.save(path)
    """

    def __init__(self, title, subtitle="", meta=None, landscape=False):
        self.doc = d = Document()
        sec = d.sections[0]
        sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)            # A4
        if landscape:
            sec.orientation = WD_ORIENT.LANDSCAPE
            sec.page_width, sec.page_height = sec.page_height, sec.page_width
        for side in ("left_margin", "right_margin"):
            setattr(sec, side, Cm(2.0))
        sec.top_margin, sec.bottom_margin = Cm(2.0), Cm(1.8)
        st = d.styles
        st["Normal"].font.name = "Calibri"
        st["Normal"].font.size = Pt(10.5)
        st["Normal"].paragraph_format.space_after = Pt(6)
        st["Normal"].paragraph_format.line_spacing = 1.12
        for name, size, before in (("Title", 24, 0), ("Heading 1", 15, 16), ("Heading 2", 12, 10), ("Heading 3", 10.5, 8)):
            s = st[name]
            s.font.name = "Calibri"
            s.font.size = Pt(size)
            s.font.bold = True
            s.font.color.rgb = _NAVY
            s.paragraph_format.space_before = Pt(before)
            s.paragraph_format.space_after = Pt(4 if name != "Title" else 2)
            s.paragraph_format.keep_with_next = True
            rpr = s.element.get_or_add_rPr()
            fonts = rpr.find(qn("w:rFonts"))
            if fonts is None:
                fonts = OxmlElement("w:rFonts")
                rpr.append(fonts)
            for a in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
                fonts.set(qn(a), "Calibri")
        z = d.settings.element.find(qn("w:zoom"))
        if z is not None and z.get(qn("w:percent")) is None:
            z.set(qn("w:percent"), "100")
        # Title block
        t = d.add_paragraph(title, style="Title")
        if subtitle:
            p = d.add_paragraph()
            r = p.add_run(subtitle)
            r.font.size, r.font.color.rgb = Pt(12), _GREY
        if meta:
            p = d.add_paragraph()
            r = p.add_run(meta)
            r.font.size, r.font.color.rgb = Pt(9), _GREY
        self._rule()
        # Header and footer
        hp = sec.header.paragraphs[0]
        hr = hp.add_run(f"Veltrix segmentation · {title}")
        hr.font.size, hr.font.color.rgb = Pt(8), _GREY
        fp = sec.footer.paragraphs[0]
        fp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        fr = fp.add_run("Page ")
        fr.font.size = Pt(8)
        r2 = fp.add_run()
        r2.font.size = Pt(8)
        _field(r2, "PAGE")
        self._fig = 0
        self._tab = 0

    def _rule(self):
        p = self.doc.add_paragraph()
        pPr = p._p.get_or_add_pPr()
        bdr = OxmlElement("w:pBdr")
        b = OxmlElement("w:bottom")
        for k, v in (("w:val", "single"), ("w:sz", "8"), ("w:space", "1"), ("w:color", "1F4E79")):
            b.set(qn(k), v)
        bdr.append(b)
        pPr.append(bdr)

    def h1(self, text):
        self.doc.add_heading(text, level=1)

    def h2(self, text):
        self.doc.add_heading(text, level=2)

    def h3(self, text):
        self.doc.add_heading(text, level=3)

    def _runs(self, p, text, size=None, color=None, italic=False):
        text = text.replace("`", "")
        for i, part in enumerate(re.split(r"\*\*", text)):
            if not part:
                continue
            r = p.add_run(part)
            r.bold = (i % 2 == 1)
            r.italic = italic
            if size:
                r.font.size = Pt(size)
            if color:
                r.font.color.rgb = color
        return p

    def p(self, text, size=None, italic=False, muted=False):
        return self._runs(self.doc.add_paragraph(), text, size=size, italic=italic, color=_GREY if muted else None)

    def callout(self, text):
        """A shaded one-cell box for the key message."""
        t = self.doc.add_table(rows=1, cols=1)
        c = t.cell(0, 0)
        _shade(c, "FDF1E9")
        c.paragraphs[0].paragraph_format.space_after = Pt(2)
        self._runs(c.paragraphs[0], text)
        self.doc.add_paragraph().paragraph_format.space_after = Pt(0)

    def bullets(self, items, style="List Bullet"):
        for it in items:
            p = self.doc.add_paragraph(style=style)
            p.paragraph_format.space_after = Pt(2)
            self._runs(p, it)

    def numbered(self, items):
        self.bullets(items, style="List Number")

    def kpis(self, pairs):
        """A row of headline numbers: [(value, label), ...]."""
        t = self.doc.add_table(rows=2, cols=len(pairs))
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        for j, (v, lab) in enumerate(pairs):
            for i in range(2):
                _shade(t.cell(i, j), "F3F4F6")
            r = t.cell(0, j).paragraphs[0].add_run(str(v))
            r.bold, r.font.size, r.font.color.rgb = True, Pt(16), _NAVY
            r = t.cell(1, j).paragraphs[0].add_run(lab)
            r.font.size, r.font.color.rgb = Pt(8.5), _GREY
        self.doc.add_paragraph().paragraph_format.space_after = Pt(0)

    def table(self, df, widths_cm=None, caption=None, font=8.5, max_rows=None, index=False):
        if index:
            df = df.reset_index()
        if max_rows is not None:
            df = df.head(max_rows)
        if caption:
            self._tab += 1
            cp = self.doc.add_paragraph()
            r = cp.add_run(f"Table {self._tab}. {caption}")
            r.bold, r.font.size, r.font.color.rgb = True, Pt(9), _GREY
            cp.paragraph_format.keep_with_next = True
            cp.paragraph_format.space_after = Pt(2)
        t = self.doc.add_table(rows=len(df) + 1, cols=len(df.columns))
        t.style = "Table Grid"
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        for j, col in enumerate(df.columns):
            c = t.cell(0, j)
            _shade(c, "1F4E79")
            r = c.paragraphs[0].add_run(str(col))
            r.bold, r.font.size, r.font.color.rgb = True, Pt(font), RGBColor(0xFF, 0xFF, 0xFF)
        # repeat header row on each page
        trPr = t.rows[0]._tr.get_or_add_trPr()
        th = OxmlElement("w:tblHeader")
        th.set(qn("w:val"), "true")
        trPr.append(th)
        for i, row in enumerate(df.itertuples(index=False), start=1):
            for j, v in enumerate(row):
                c = t.cell(i, j)
                if i % 2 == 0:
                    _shade(c, "F3F4F6")
                if isinstance(v, float):
                    s = "" if pd.isna(v) else (f"{v:,.0f}" if abs(v) >= 100 else f"{v:,.2f}".rstrip("0").rstrip("."))
                elif isinstance(v, int) and not isinstance(v, bool):
                    s = f"{v:,}"
                else:
                    s = "" if v is None or (not isinstance(v, str) and pd.isna(v)) else str(v)
                p = c.paragraphs[0]
                p.paragraph_format.space_after = Pt(0)
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
                r = p.add_run(s)
                r.font.size = Pt(font)
        if widths_cm is None:     # share 17 cm in proportion to the longest text in each column
            lens = [max([len(str(c)) for c in df.columns[j:j + 1]] + [len(str(v)) for v in df.iloc[:, j].head(50)]) for j in range(len(df.columns))]
            lens = [min(max(L, 4), 40) for L in lens]
            widths_cm = [17.0 * L / sum(lens) for L in lens]
        t.autofit = False                     # python-docx writes <w:tblLayout w:type="fixed"/>
        for j, w in enumerate(widths_cm):
            t.columns[j].width = Cm(w)
            for cell in t.columns[j].cells:
                cell.width = Cm(w)
        self.doc.add_paragraph().paragraph_format.space_after = Pt(2)
        return t

    def image(self, path, caption=None, width_cm=16.5):
        p = self.doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.keep_with_next = True
        p.add_run().add_picture(str(path), width=Cm(width_cm))
        if caption:
            self._fig += 1
            cp = self.doc.add_paragraph()
            r = cp.add_run(f"Figure {self._fig}. {caption}")
            r.italic, r.font.size, r.font.color.rgb = True, Pt(8.5), _GREY

    def page_break(self):
        self.doc.add_page_break()

    def save(self, path):
        self.doc.save(str(path))
        print("Saved", Path(path).relative_to(ROOT) if str(path).startswith(str(ROOT)) else path)
        return None
