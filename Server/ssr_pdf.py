"""
IQAC SSR / NAAC PDF Generator
==============================
Generates an A4-portrait document following the NAAC Self Study Report
manual table layout (University cycle):

  Cover Page
  1. Executive Summary
  2. Profile of the University   <- exact NAAC form table style
  3. Extended Profile of the University
  4. Quality Indicator Framework

Dependencies: reportlab >= 4.2
"""
from __future__ import annotations

import io
from datetime import date, datetime
from typing import Any

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate,
    CondPageBreak,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.frames import Frame

# ---------------------------------------------------------------------------
# Page geometry
# ---------------------------------------------------------------------------
PAGE_W, PAGE_H = A4          # 595.28 x 841.89 pts
LEFT_MARGIN   = 1.45 * cm
RIGHT_MARGIN  = 1.45 * cm
TOP_MARGIN    = 1.55 * cm
BOTTOM_MARGIN = 1.55 * cm
BODY_W = PAGE_W - LEFT_MARGIN - RIGHT_MARGIN
BODY_H = PAGE_H - TOP_MARGIN - BOTTOM_MARGIN

NAAC_FOOTER = "NAAC for Quality and Excellence in Higher Education"

# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

def _make_styles() -> dict:
    T   = "Times-Roman"
    TB  = "Times-Bold"
    TI  = "Times-Italic"

    def ps(name, **kw):
        defaults = dict(fontName=T, fontSize=10, leading=14, textColor=colors.black)
        defaults.update(kw)
        return ParagraphStyle(name, **defaults)

    return {
        "H_COVER":   ps("H_COVER",   fontName=TB, fontSize=16, leading=22, alignment=TA_CENTER, spaceAfter=8),
        "H_SUB":     ps("H_SUB",     fontName=TI, fontSize=13, leading=18, alignment=TA_CENTER, spaceAfter=6),
        "H1":        ps("H1",        fontName=TB, fontSize=13, leading=18, alignment=TA_CENTER, spaceAfter=10),
        "H2":        ps("H2",        fontName=TB, fontSize=11, leading=15, alignment=TA_LEFT,   spaceBefore=10, spaceAfter=6),
        "H2U":       ps("H2U",       fontName=TB, fontSize=11, leading=15, alignment=TA_CENTER, spaceBefore=10, spaceAfter=6),
        "H3":        ps("H3",        fontName=TB, fontSize=10, leading=14, alignment=TA_LEFT,   spaceBefore=6, spaceAfter=4),
        "BODY":      ps("BODY",      alignment=TA_JUSTIFY, spaceAfter=5),
        "BODY_C":    ps("BODY_C",    alignment=TA_CENTER,  spaceAfter=5),
        "BODY_SMALL":ps("BODY_SMALL",fontSize=9, leading=12, alignment=TA_JUSTIFY, spaceAfter=3),
        "INSTRUCTION":ps("INSTRUCTION", fontName=TI, fontSize=9, leading=13, alignment=TA_JUSTIFY,
                          spaceAfter=5, textColor=colors.HexColor("#444444")),
        "CELL":      ps("CELL",      fontSize=9, leading=12.5, alignment=TA_LEFT),
        "CELL_B":    ps("CELL_B",    fontName=TB, fontSize=9, leading=12.5, alignment=TA_LEFT),
        "CELL_C":    ps("CELL_C",    fontSize=9, leading=12.5, alignment=TA_CENTER),
        "CELL_I":    ps("CELL_I",    fontName=TI, fontSize=9, leading=12.5, alignment=TA_LEFT,
                         textColor=colors.HexColor("#444444")),
        "FOOTER":    ps("FOOTER",    fontSize=8, leading=10, alignment=TA_CENTER,
                         textColor=colors.HexColor("#555555")),
    }


S = _make_styles()

# ---------------------------------------------------------------------------
# Table style constants
# ---------------------------------------------------------------------------
_BK = colors.black
_PAD = [
    ("TOPPADDING",    (0, 0), (-1, -1), 4),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ("LEFTPADDING",   (0, 0), (-1, -1), 4),
    ("RIGHTPADDING",  (0, 0), (-1, -1), 4),
    ("FONTSIZE",      (0, 0), (-1, -1), 9),
    ("LEADING",       (0, 0), (-1, -1), 12.5),
    ("VALIGN",        (0, 0), (-1, -1), "TOP"),
]

def _ts(*extra):
    return TableStyle(list(_PAD) + list(extra))

def _label_col_style(*extra):
    return _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (0, -1),  "Times-Bold"),
        *extra,
    )


# ---------------------------------------------------------------------------
# Footer canvas mixin
# ---------------------------------------------------------------------------
class _FooterCanvas:
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self._draw_footer(num_pages)
            super().showPage()
        super().save()

    def _draw_footer(self, page_count):
        self.saveState()
        self.setFont("Times-Roman", 8)
        self.setFillColor(colors.HexColor("#555555"))
        self.drawCentredString(
            PAGE_W / 2,
            BOTTOM_MARGIN / 2,
            f"{NAAC_FOOTER}  |  Page {self._pageNumber} of {page_count}",
        )
        self.restoreState()


# ---------------------------------------------------------------------------
# Primitive helpers
# ---------------------------------------------------------------------------
def _p(text, style="BODY"):
    text = str(text or "").strip()
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "<br/>")
    return Paragraph(text, S[style])


def _c(text, style="CELL"):
    return _p(text, style)


def _blank(h=4):
    return Spacer(1, h)


def _val(data, *keys, default=""):
    cur = data
    for k in keys:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k, default)
    return cur if cur is not None else default


def _s(data, *keys) -> str:
    return str(_val(data, *keys, default="")).strip()


def _rows(data, *keys) -> list:
    v = _val(data, *keys, default=[])
    return v if isinstance(v, list) else []


def _d(v) -> dict:
    return v if isinstance(v, dict) else {}


def _yes_no_marks(value: Any) -> tuple[str, str]:
    normalized = str(value or "").strip().lower()
    if normalized in {"yes", "y", "true", "1"}:
        return "X", ""
    if normalized in {"no", "n", "false", "0"}:
        return "", "X"
    return "", ""


def _table(data_rows, col_widths, style, repeat_rows=0):
    """Reusable NAAC table renderer: wrapped text, even borders, dynamic row height."""
    t = Table(
        data_rows,
        colWidths=col_widths,
        repeatRows=repeat_rows,
        splitByRow=1,
        hAlign="LEFT",
    )
    t.setStyle(style)
    return t


def _flowable_height(flowable, width=BODY_W) -> float:
    _, height = flowable.wrap(width, BODY_H)
    return height


def _flowables_height(flowables, width=BODY_W) -> float:
    return sum(_flowable_height(flowable, width) for flowable in flowables)


def _section_block(
    title: str,
    body: list,
    title_style: str = "H2",
    before: float = 7,
    after: float = 8,
    keep_if_fits: bool = True,
    min_start_height: float = 76,
) -> list:
    """Section component with intelligent page breaking.

    Small sections are kept whole. Large sections are allowed to split, but only
    after ReportLab has enough room for the heading and the first body rows.
    """
    elements = []
    if before:
        elements.append(_blank(before))
    if title:
        elements.append(_p(title, title_style))
        elements.append(_blank(3))
    elements.extend(body)
    if after:
        elements.append(_blank(after))

    full_height = _flowables_height(elements)
    if keep_if_fits and full_height <= BODY_H * 0.92:
        return [CondPageBreak(full_height), KeepTogether(elements)]

    minimum_start_height = min(full_height, min_start_height)
    return [CondPageBreak(minimum_start_height), *elements]


def _header_table(data_rows, col_widths, style, repeat_rows=1):
    """Header row component for tables that may span pages."""
    return _table(data_rows, col_widths, style, repeat_rows=repeat_rows)


# ---------------------------------------------------------------------------
# Cover page
# ---------------------------------------------------------------------------
def _build_cover(sections_data: dict, meta: dict) -> list:
    p = _d(sections_data.get("university_profile"))
    basic = _d(p.get("basic_information"))
    inst_name = _s(basic, "name") or "Institution"

    generated_by = meta.get("generated_by") or "IQAC Administrator"
    generated_at = meta.get("generated_at")
    if isinstance(generated_at, datetime):
        ts = generated_at.strftime("%d %B %Y, %I:%M %p") + " (UTC)"
    else:
        ts = datetime.utcnow().strftime("%d %B %Y, %I:%M %p") + " (UTC)"

    story = []
    story.append(Spacer(1, 3 * cm))
    story.append(_blank(16))
    story.append(_p("SELF STUDY REPORT", "H_COVER"))
    story.append(_p("(SSR)", "H_COVER"))
    story.append(_blank(8))
    story.append(_p("Submitted to", "H_SUB"))
    story.append(_blank(4))
    story.append(_p("National Assessment and Accreditation Council", "H1"))
    story.append(_p("(NAAC)", "H1"))
    story.append(_blank(4))
    story.append(_p("Bengaluru - 560 072, Karnataka", "BODY_C"))
    story.append(_blank(20))
    story.append(_p(inst_name, "H1"))
    story.append(_blank(16))

    addr_parts = [_s(basic, k) for k in ("address", "city", "state", "pin") if _s(basic, k)]
    detail_data = [
        [_c("Address",      "CELL_B"), _c(", ".join(addr_parts) or "-")],
        [_c("Website",      "CELL_B"), _c(_s(basic, "website") or "-")],
        [_c("Generated by", "CELL_B"), _c(generated_by)],
        [_c("Generated on", "CELL_B"), _c(ts)],
        [_c("System",       "CELL_B"), _c("IQAC SSR / NAAC Data Entry Portal")],
    ]
    story.append(_table(detail_data, [BODY_W * 0.25, BODY_W * 0.75], _label_col_style()))
    story.append(PageBreak())
    return story


# ---------------------------------------------------------------------------
# Section 1 - Executive Summary
# ---------------------------------------------------------------------------
def _build_executive_summary(data: dict) -> list:
    es = _d(data.get("executive_summary"))
    story = []
    story.append(_p("1. Executive Summary", "H1"))
    story.append(_blank())
    story.append(_p(
        "Every Higher Education Institution (HEI) applying for the Accreditation and "
        "Assessment (A&A) process shall prepare an Executive Summary highlighting the main "
        "features of the Institution. The Executive Summary shall not be more than 5000 words.",
        "INSTRUCTION",
    ))
    story.append(_blank(6))

    fields = [
        ("1.1 Introductory Note on the Institution", "introductory_note",
         "Provide a brief introduction covering location, type, founding year, vision, mission, "
         "and key characteristics."),
        ("1.2 Criterion-wise Summary", "criteria_summary",
         "Summarise the institution's functioning criterion-wise in not more than 250 words "
         "for each of the seven criteria."),
        ("1.3 SWOC Analysis", "swoc_analysis",
         "Provide a brief note on Strengths, Weaknesses, Opportunities and Challenges."),
        ("1.4 Additional Information about the Institution", "additional_information",
         "Any additional information about the institution other than already stated above."),
        ("1.5 Overall Conclusive Explication", "conclusive_explication",
         "Overall conclusive explication about the institution's functioning."),
    ]

    for heading, key, instruction in fields:
        story.append(_p(heading, "H2"))
        story.append(_p(instruction, "INSTRUCTION"))
        content = _s(es, key)
        if content:
            for para in content.split("\n"):
                para = para.strip()
                if para:
                    story.append(_p(para, "BODY"))
        else:
            story.append(_blank(8))
        story.append(_blank(6))

    return story


# ---------------------------------------------------------------------------
# Section 2 - Profile of the University  (NAAC form-faithful layout)
# ---------------------------------------------------------------------------

def _build_profile(data: dict) -> list:
    p = _d(data.get("university_profile"))
    story: list = []
    story.append(PageBreak())
    story.append(_p("2.  Profile of the University", "H1"))
    story.append(_blank(4))

    # --- Basic Information --------------------------------------------------
    basic = _d(p.get("basic_information"))
    cw4 = [BODY_W * 0.14, BODY_W * 0.36, BODY_W * 0.14, BODY_W * 0.36]

    bi_data = [
        [_c("Name and Address of the University", "CELL_B"), _c(""), _c(""), _c("")],
        [_c("Name",    "CELL_B"), _c(_s(basic, "name")),    _c(""),                   _c("")],
        [_c("Address", "CELL_B"), _c(_s(basic, "address")), _c(""),                   _c("")],
        [_c("City",    "CELL_B"), _c(_s(basic, "city")),    _c("Pin",     "CELL_B"),  _c(_s(basic, "pin"))],
        [_c("State",   "CELL_B"), _c(_s(basic, "state")),   _c("Website", "CELL_B"),  _c(_s(basic, "website"))],
    ]
    bi_style = _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("SPAN",     (0, 0), (3, 0)),
        ("FONTNAME", (0, 0), (3, 0),  "Times-Bold"),
        ("SPAN",     (1, 1), (3, 1)),
        ("SPAN",     (1, 2), (3, 2)),
        ("FONTNAME", (0, 1), (0, -1), "Times-Bold"),
    )
    story.extend(_section_block(
        "Basic Information",
        [_table(bi_data, cw4, bi_style)],
        title_style="H2U",
    ))

    # --- Contacts for Communication -----------------------------------------
    contacts_raw = p.get("contacts")
    ct_cw = [BODY_W*0.18, BODY_W*0.17, BODY_W*0.17, BODY_W*0.14, BODY_W*0.10, BODY_W*0.24]
    ct_hdr = [_c(h, "CELL_B") for h in
              ("Designation", "Name", "Telephone\nwith STD Code", "Mobile", "Fax", "Email")]
    ct_data = [ct_hdr]

    if isinstance(contacts_raw, list):
        for c in contacts_raw:
            if not isinstance(c, dict):
                continue
            ct_data.append([
                _c(_s(c, "designation")), _c(_s(c, "name")),
                _c(_s(c, "telephone")),   _c(_s(c, "mobile")),
                _c(_s(c, "fax")),         _c(_s(c, "email")),
            ])
    elif isinstance(contacts_raw, dict):
        for rk, lbl in [("head_of_institution", "Head of Institution"),
                         ("iqac_coordinator",    "IQAC Coordinator")]:
            c = _d(contacts_raw.get(rk))
            ct_data.append([
                _c(_s(c, "designation") or lbl), _c(_s(c, "name")),
                _c(_s(c, "telephone")),
                _c(_s(c, "mobile") or _s(c, "phone")),
                _c(_s(c, "fax")), _c(_s(c, "email")),
            ])

    if len(ct_data) == 1:
        ct_data.append([_c("(No contacts entered)")] + [_c("")] * 5)

    story.extend(_section_block(
        "Contacts for Communication",
        [_header_table(ct_data, ct_cw, _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        ))],
        title_style="H2U",
    ))

    # --- Nature / Type / Establishment table --------------------------------
    inst  = _d(p.get("institution"))
    estab = _d(p.get("establishment"))
    recog = _d(p.get("recognition"))

    nat_data = [
        [_c("Nature of University",   "CELL_B"), _c(_s(inst, "nature")),
         _c("Institution Status",      "CELL_B"), _c(_s(inst, "status"))],
        [_c("Type of University",     "CELL_B"), _c(_s(inst, "type")),
         _c("Type of University",      "CELL_B"), _c(_s(inst, "type"))],
        [_c("Establishment\nDetails", "CELL_B"),
         _c("Establishment Date of the University"),
         _c(_s(estab, "establishment_date")), _c("")],
        [_c("", "CELL_B"),
         _c("Status Prior to Establishment, If applicable"),
         _c(_s(estab, "status_prior")),
         _c("(Autonomous, Constituent, PG Centre, any other)")],
        [_c("", "CELL_B"),
         _c("Establishment date"),
         _c(_s(estab, "establishment_date_if_applicable")), _c("")],
    ]
    cw4b = [BODY_W * 0.16, BODY_W * 0.34, BODY_W * 0.16, BODY_W * 0.34]
    nat_style = _ts(
        ("GRID",    (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME",(0, 0), (0, -1),  "Times-Bold"),
        ("SPAN",    (0, 2), (0, 4)),
        ("VALIGN",  (0, 2), (0, 4), "MIDDLE"),
    )
    story.extend(_section_block("", [_table(nat_data, cw4b, nat_style)], before=0, after=7))

    # --- Recognition Details ------------------------------------------------
    ugc_2f  = _s(recog, "ugc_2f_date")  or _s(recog, "ugc_recognition_date")
    ugc_12b = _s(recog, "ugc_12b_date") or _s(recog, "section_12b")

    rec_data = [
        [_c("Date of Recognition as a University by UGC or Any Other National Agency", "CELL_B"),
         _c(""), _c("")],
        [_c("Under Section", "CELL_B"), _c("Date", "CELL_B"), _c("")],
        [_c("2f of UGC"),    _c(ugc_2f),   _c("")],
        [_c("12B of UGC"),   _c(ugc_12b),  _c("")],
    ]
    cw3 = [BODY_W * 0.40, BODY_W * 0.30, BODY_W * 0.30]
    rec_style = _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("SPAN",     (0, 0), (2, 0)),
        ("FONTNAME", (0, 0), (2, 0),  "Times-Bold"),
        ("FONTNAME", (0, 1), (1, 1),  "Times-Bold"),
        ("SPAN",     (1, 2), (2, 2)),
        ("SPAN",     (1, 3), (2, 3)),
    )
    recognition_body = [_table(rec_data, cw3, rec_style)]

    other_agencies = _rows(recog, "other_agencies")
    if other_agencies:
        ag_data = [[_c("Sl.", "CELL_B"),
                    _c("Statutory Regulatory Authority", "CELL_B"),
                    _c("Recognition / Approval", "CELL_B")]]
        for i, row in enumerate(other_agencies, 1):
            ag_data.append([_c(str(i), "CELL_C"),
                              _c(_s(row, "agency")), _c(_s(row, "recognition"))])
        recognition_body.append(_header_table(ag_data, [BODY_W*0.08, BODY_W*0.52, BODY_W*0.40], _ts(
            ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
            ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        )))

    story.extend(_section_block("Recognition Details", recognition_body, title_style="H2U"))

    # --- University with Potential for Excellence ---------------------------
    yes_tick, no_tick = _yes_no_marks(_s(p, "upe_recognized"))

    upe_data = [
        [_c("Is the University Recognised as a 'University with Potential for "
            "Excellence (UPE)' by the UGC?", "CELL_B"),
         _c("Yes", "CELL_C"), _c("No", "CELL_C")],
        [_c(""), _c(yes_tick, "CELL_C"), _c(no_tick, "CELL_C")],
    ]
    upe_cw = [BODY_W * 0.72, BODY_W * 0.14, BODY_W * 0.14]
    story.extend(_section_block(
        "University with Potential for Excellence",
        [_table(upe_data, upe_cw, _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (2, 0),   "Times-Bold"),
        ("SPAN",     (0, 0), (0, 1)),
        ("VALIGN",   (0, 0), (0, 1), "MIDDLE"),
        ))],
        title_style="H2U",
    ))

    # --- Location, Area and Activity of Campus ------------------------------
    campuses = _rows(p, "campuses")
    LOCATIONS = ["Urban", "Semi Urban", "Rural", "Tribal", "Hill"]
    camp_hdr = [_c(h, "CELL_B") for h in (
        "Campus\nType", "Address", "Location",
        "Campus Area\nAcres", "Built up\nArea in\nsq.mts.",
        "Programmes\nOffered", "Date of\nEstablishment",
        "Date of\nRecognition by\nUGC/MHRD",
    )]
    camp_cw = [BODY_W*0.09, BODY_W*0.14, BODY_W*0.14,
               BODY_W*0.10, BODY_W*0.10, BODY_W*0.15,
               BODY_W*0.14, BODY_W*0.14]
    camp_data = [camp_hdr]
    if campuses:
        for camp in campuses:
            camp_data.append([
                _c(_s(camp, "campus_type")),
                _c(_s(camp, "address")),
                _c(_s(camp, "location")),
                _c(_s(camp, "campus_area_acres")),
                _c(_s(camp, "built_up_area_sq_mts")),
                _c(_s(camp, "programmes_offered")),
                _c(_s(camp, "establishment_date")),
                _c(_s(camp, "recognition_date")),
            ])
    else:
        camp_data.append([_c(""), _c(""), _c("\n".join(LOCATIONS)),
                           _c(""), _c(""), _c(""), _c(""), _c("")])
    story.extend(_section_block(
        "Location, Area and Activity of Campus",
        [_header_table(camp_data, camp_cw, _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        ))],
        title_style="H2U",
    ))

    # --- Academic Information -----------------------------------------------
    ai = _d(p.get("academic_information"))
    academic_body = [
        _p(
            "Affiliated Institutions to the University "
            "(Not applicable for private and deemed to be Universities)", "BODY_SMALL"
        )
    ]

    # Table 1: College Type / Perm / Temp
    aff_rows = _rows(ai, "affiliated_institutions")
    aff1_data = [[_c("College Type", "CELL_B"),
                   _c("Number of colleges with\npermanent affiliation", "CELL_B"),
                   _c("Number of colleges with\ntemporary affiliation", "CELL_B")]]
    for row in (aff_rows if aff_rows else [{}]):
        aff1_data.append([_c(_s(row, "college_type")),
                            _c(_s(row, "permanent_affiliation")),
                            _c(_s(row, "temporary_affiliation"))])
    academic_body.append(_header_table(aff1_data, [BODY_W*0.40, BODY_W*0.30, BODY_W*0.30], _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        ("ALIGN",    (1, 1), (-1, -1), "CENTER"),
    )))
    academic_body.append(_blank(5))

    # Table 2: Type of Colleges / Perm / Temp / Total
    ct_rows = _rows(ai, "college_type_affiliations")
    if not ct_rows:
        ct_rows = [
            {"college_type": "Education/Teachers Training"},
            {"college_type": "Business administration/\nCommerce/Management/Finance"},
            {"college_type": "Universal/Common to all\nDisciplines"},
        ]
    aff2_data = [[_c("Type of Colleges", "CELL_B"), _c("Permanent", "CELL_B"),
                   _c("Temporary", "CELL_B"), _c("Total", "CELL_B")]]
    for row in ct_rows:
        aff2_data.append([
            _c(_s(row, "college_type")),
            _c(_s(row, "permanent") or _s(row, "permanent_affiliation")),
            _c(_s(row, "temporary") or _s(row, "temporary_affiliation")),
            _c(_s(row, "total")),
        ])
    academic_body.append(_header_table(aff2_data, [BODY_W*0.46, BODY_W*0.18, BODY_W*0.18, BODY_W*0.18], _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        ("ALIGN",    (1, 1), (-1, -1), "CENTER"),
    )))
    academic_body.append(_blank(5))

    # Table 3: College details
    college_details = _rows(ai, "college_details")
    if not college_details:
        college_details = [
            {"label": "Constituent Colleges"},
            {"label": "Affiliated Colleges"},
            {"label": "Colleges Under 2(f)"},
            {"label": "Colleges Under 2(f) and 12B"},
            {"label": "NAAC Accredited Colleges"},
            {"label": "Colleges with Potential for Excellence (UGC)"},
            {"label": "Autonomous Colleges"},
            {"label": "Colleges with Postgraduate Departments"},
            {"label": "Colleges with Research Departments"},
            {"label": "University Recognized Research Institutes/Centers"},
        ]
    academic_body.append(_p("Furnish the Details of Colleges under University", "H3"))
    cd_data = [[_c(_s(r, "label"), "CELL_B"), _c(_s(r, "value"))] for r in college_details]
    academic_body.append(_table(cd_data, [BODY_W*0.75, BODY_W*0.25], _label_col_style(
        ("ALIGN", (1, 0), (1, -1), "CENTER"),
    )))
    academic_body.append(_blank(5))

    # SRA Yes/No
    sra_yes, sra_no = _yes_no_marks(_s(ai, "sra_recognized"))
    sra_data = [
        [_c("Is the University Offering any Programmes Recognized by any "
            "Statutory Regulatory authority (SRA)", "CELL_B"),
         _c("Yes", "CELL_C"), _c("No", "CELL_C")],
        [_c(""), _c(sra_yes, "CELL_C"), _c(sra_no, "CELL_C")],
    ]
    academic_body.append(_table(sra_data, [BODY_W*0.72, BODY_W*0.14, BODY_W*0.14], _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (2, 0),   "Times-Bold"),
        ("SPAN",     (0, 0), (0, 1)),
        ("VALIGN",   (0, 0), (0, 1), "MIDDLE"),
    )))
    story.extend(_section_block("Academic Information", academic_body, title_style="H2U", keep_if_fits=False))

    # --- Teaching & Non-Teaching Staff -------------------------------------
    staff = _d(p.get("staff"))
    staff_body = []
    ROLES_T   = ["Professor", "Associate Professor", "Assistant Professor"]
    GENDERS_T = ["Male", "Female", "Others", "Total"]
    STATUSES  = ["Sanctioned", "Recruited", "Yet to Recruit", "On Contract"]

    staff_body.append(_p("Teaching Faculty", "H3"))
    tf_rows = _rows(staff, "teaching")

    # Two header rows with role spans
    th1 = (
        [_c("", "CELL_B")] +
        [_c("Professor", "CELL_B"),            _c("","CELL_B"), _c("","CELL_B"), _c("","CELL_B")] +
        [_c("Associate Professor", "CELL_B"),   _c("","CELL_B"), _c("","CELL_B"), _c("","CELL_B")] +
        [_c("Assistant Professor", "CELL_B"),   _c("","CELL_B"), _c("","CELL_B"), _c("","CELL_B")] +
        [_c("Total", "CELL_B")]
    )
    th2 = (
        [_c("", "CELL_B")] +
        [_c(g, "CELL_B") for g in GENDERS_T] * 3 +
        [_c("", "CELL_B")]
    )
    tf_cw = [BODY_W*0.12] + [BODY_W*0.068]*12 + [BODY_W*0.04]
    tf_data = [th1, th2]
    for row in (tf_rows if tf_rows else [{"status": s} for s in STATUSES]):
        cells = [_c(_s(row, "status"))]
        for role in ROLES_T:
            for g in GENDERS_T:
                cells.append(_c(_s(row, f"{role}_{g}")))
        cells.append(_c(_s(row, "Total")))
        tf_data.append(cells)

    staff_body.append(_header_table(tf_data, tf_cw, _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 1),  "Times-Bold"),
        ("SPAN",     (1, 0), (4, 0)),
        ("SPAN",     (5, 0), (8, 0)),
        ("SPAN",     (9, 0), (12, 0)),
        ("SPAN",     (13, 0), (13, 1)),
        ("SPAN",     (0, 0), (0, 1)),
        ("VALIGN",   (0, 0), (-1, 1), "MIDDLE"),
        ("ALIGN",    (1, 0), (-1, 0), "CENTER"),
        ("ALIGN",    (1, 1), (-1, -1), "CENTER"),
    ), repeat_rows=2))
    staff_body.append(_blank(7))

    for group_lbl, group_key in [("Non- Teaching Staff", "non_teaching"),
                                   ("Technical Staff", "technical")]:
        staff_body.append(_p(group_lbl, "H3"))
        g_rows = _rows(staff, group_key)
        nt_hdr = [_c("", "CELL_B")] + [_c(g, "CELL_B") for g in ("Male", "Female", "Others", "Total")]
        nt_cw  = [BODY_W*0.30] + [BODY_W*0.175]*4
        nt_data = [nt_hdr]
        for row in (g_rows if g_rows else [{"status": s} for s in STATUSES]):
            nt_data.append([_c(_s(row, "status")),
                              _c(_s(row, "Male")), _c(_s(row, "Female")),
                              _c(_s(row, "Others")), _c(_s(row, "Total"))])
        staff_body.append(_header_table(nt_data, nt_cw, _ts(
            ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
            ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
            ("ALIGN",    (1, 1), (-1, -1), "CENTER"),
        )))
        staff_body.append(_blank(7))

    story.extend(_section_block(
        "Details of Teaching & Non-Teaching Staff of University",
        staff_body,
        keep_if_fits=False,
    ))

    # --- Qualification Details ----------------------------------------------
    qual = _d(p.get("qualification_details"))
    QUALIFICATIONS = ["D.sc/D.Litt", "Ph.D.", "M.Phil.", "PG"]
    qcw = [BODY_W*0.15] + [BODY_W*0.075]*9 + [BODY_W*0.175]

    for index, (grp_lbl, grp_key) in enumerate([
        ("Permanent Teachers", "permanent_teachers"),
        ("Temporary Teachers", "temporary_teachers"),
        ("Part Time Teachers", "part_time_teachers"),
    ]):
        q_rows = _rows(qual, grp_key)
        qh1 = (
            [_c("Highest\nQualification", "CELL_B")] +
            [_c("Professor", "CELL_B"),            _c("","CELL_B"), _c("","CELL_B")] +
            [_c("Associate\nProfessor", "CELL_B"),  _c("","CELL_B"), _c("","CELL_B")] +
            [_c("Assistant\nProfessor", "CELL_B"),  _c("","CELL_B"), _c("","CELL_B")] +
            [_c("Total", "CELL_B")]
        )
        qh2 = (
            [_c("", "CELL_B")] +
            [_c(g, "CELL_B") for g in ("Male", "Female", "Others")] * 3 +
            [_c("", "CELL_B")]
        )
        q_data = [qh1, qh2]
        for row in (q_rows if q_rows else [{"qualification": q} for q in QUALIFICATIONS]):
            cells = [_c(_s(row, "qualification"))]
            for role_k in ["Professor", "Associate Professor", "Assistant Professor"]:
                for g in ("Male", "Female", "Others"):
                    cells.append(_c(_s(row, f"{role_k}_{g}")))
            cells.append(_c(_s(row, "Total")))
            q_data.append(cells)

        title_table = _table([[_c(grp_lbl, "CELL_B")]], [BODY_W],
                             _ts(("GRID",(0,0),(-1,-1),0.5,_BK),
                                 ("ALIGN",(0,0),(-1,-1),"CENTER"),
                                 ("FONTNAME",(0,0),(-1,-1),"Times-Bold")))
        qualification_table = _header_table(q_data, qcw, _ts(
            ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
            ("FONTNAME", (0, 0), (-1, 1),  "Times-Bold"),
            ("SPAN",     (1, 0), (3, 0)),
            ("SPAN",     (4, 0), (6, 0)),
            ("SPAN",     (7, 0), (9, 0)),
            ("SPAN",     (10, 0),(10, 1)),
            ("SPAN",     (0, 0), (0,  1)),
            ("VALIGN",   (0, 0), (-1, 1), "MIDDLE"),
            ("ALIGN",    (0, 0), (-1, 0), "CENTER"),
            ("ALIGN",    (1, 1), (-1, -1), "CENTER"),
        ), repeat_rows=2)
        if index == 0:
            story.extend(_section_block(
                "Qualification Details of the Teaching Staff",
                [title_table, qualification_table],
                after=7,
                keep_if_fits=False,
                min_start_height=140,
            ))
        else:
            story.extend(_section_block(
                "",
                [title_table, qualification_table],
                before=4,
                after=7,
                keep_if_fits=False,
                min_start_height=112,
            ))

    # --- Distinguished Academicians ----------------------------------------
    da_rows = _rows(p, "distinguished_academicians")
    if not da_rows:
        da_rows = [{"role": r} for r in ("Emeritus Professor", "Adjunct Professor", "Visiting Professor")]
    da_hdr = [_c("", "CELL_B")] + [_c(g, "CELL_B") for g in ("Male", "Female", "Others", "Total")]
    da_cw  = [BODY_W*0.30] + [BODY_W*0.175]*4
    da_data = [da_hdr]
    for row in da_rows:
        da_data.append([_c(_s(row, "role")),
                         _c(_s(row, "male")), _c(_s(row, "female")),
                         _c(_s(row, "others")), _c(_s(row, "total"))])
    story.extend(_section_block("Distinguished Academicians Appointed", [_header_table(da_data, da_cw, _ts(
        ("GRID",     (0,0),(-1,-1),0.5,_BK),
        ("FONTNAME", (0,0),(-1, 0),"Times-Bold"),
        ("ALIGN",    (1,1),(-1,-1),"CENTER"),
    ))], min_start_height=90))

    # --- Chairs Instituted -------------------------------------------------
    chairs = _rows(p, "chairs")
    ch_hdr = [_c("Sl.No", "CELL_B"), _c("Name of the\nDepartment", "CELL_B"),
              _c("Name of the\nChair", "CELL_B"),
              _c("Name of the Sponsor\nOrganisation/Agency", "CELL_B")]
    ch_cw = [BODY_W*0.10, BODY_W*0.27, BODY_W*0.27, BODY_W*0.36]
    ch_data = [ch_hdr]
    for i, row in enumerate(chairs if chairs else [{}], 1):
        ch_data.append([_c(str(i), "CELL_C"),
                         _c(_s(row, "department")), _c(_s(row, "chair")),
                         _c(_s(row, "sponsor"))])
    story.extend(_section_block("Chairs Instituted by the University", [_header_table(ch_data, ch_cw, _ts(
        ("GRID",     (0,0),(-1,-1),0.5,_BK),
        ("FONTNAME", (0,0),(-1, 0),"Times-Bold"),
        ("ALIGN",    (0,1),(0,-1),"CENTER"),
    ))], min_start_height=90))

    # --- Student Enrolment --------------------------------------------------
    enrol = _rows(p, "student_enrolment")
    se_hdr = [
        _c("Programme", "CELL_B"), _c("", "CELL_B"),
        _c("From the State Where University is Located", "CELL_B"),
        _c("From Other States of India", "CELL_B"),
        _c("NRI\nStudents", "CELL_B"),
        _c("Foreign\nStudents", "CELL_B"),
        _c("Total", "CELL_B"),
    ]
    se_cw = [BODY_W*0.14, BODY_W*0.08, BODY_W*0.18,
             BODY_W*0.18, BODY_W*0.10, BODY_W*0.10, BODY_W*0.10]  # last col fills remainder
    # Adjust last col to fill
    se_cw[-1] = BODY_W - sum(se_cw[:-1])
    se_data = [se_hdr]

    if enrol:
        prev_prog = None
        for row in enrol:
            prog   = _s(row, "programme")
            gender = _s(row, "gender")
            se_data.append([
                _c(prog if prog != prev_prog else ""),
                _c(gender),
                _c(_s(row, "from_state")),
                _c(_s(row, "from_other_states")),
                _c(_s(row, "nri")),
                _c(_s(row, "foreign")),
                _c(_s(row, "total")),
            ])
            prev_prog = prog
    else:
        for prog in ("PG", "UG", "PG Diploma recognized by statutory authority\nincluding university"):
            for gender in ("Male", "Female", "Others"):
                se_data.append([
                    _c(prog if gender == "Male" else ""), _c(gender),
                    _c(""), _c(""), _c(""), _c(""), _c(""),
                ])

    student_body = [_header_table(se_data, se_cw, _ts(
        ("GRID",     (0,0),(-1,-1),0.5,_BK),
        ("FONTNAME", (0,0),(-1, 0),"Times-Bold"),
        ("ALIGN",    (2,1),(-1,-1),"CENTER"),
    ))]
    story.extend(_section_block(
        "Provide the Following Details of Students Enrolled in the University during the Current Academic Year",
        student_body,
        keep_if_fits=False,
        min_start_height=100,
    ))

    # --- Integrated Programmes ----------------------------------------------
    integ    = _d(p.get("integrated_programmes"))
    ip_yes, ip_no = _yes_no_marks(_s(integ, "offered"))
    ip_total = _s(integ, "total_programmes")
    ip_enrol = _rows(integ, "enrolment")

    integrated_body = [_table(
        [[_c("Does the university offer any integrated programmes?", "CELL_B"),
          _c("Yes", "CELL_C"), _c("No", "CELL_C")],
         [_c(""), _c(ip_yes, "CELL_C"), _c(ip_no, "CELL_C")]],
        [BODY_W*0.72, BODY_W*0.14, BODY_W*0.14],
        _ts(
            ("GRID",(0,0),(-1,-1),0.5,_BK),
            ("FONTNAME",(0,0),(2,0),"Times-Bold"),
            ("SPAN",(0,0),(0,1)),
            ("VALIGN",(0,0),(0,1),"MIDDLE"),
        ),
    )]
    integrated_body.append(_table(
        [[_c("Total number of integrated programme", "CELL_B"), _c(ip_total)]],
        [BODY_W*0.60, BODY_W*0.40],
        _ts(("GRID",(0,0),(-1,-1),0.5,_BK), ("FONTNAME",(0,0),(0,0),"Times-Bold")),
    ))
    ip_hdr = [
        _c("Integrated\nProgramme", "CELL_B"),
        _c("From the state where\nuniversity is located", "CELL_B"),
        _c("From other states\nof India", "CELL_B"),
        _c("NRI Students", "CELL_B"),
        _c("Foreign\nStudents", "CELL_B"),
        _c("Total", "CELL_B"),
    ]
    ip_cw = [BODY_W*0.17, BODY_W*0.21, BODY_W*0.21, BODY_W*0.14, BODY_W*0.13, BODY_W*0.14]
    ip_data = [ip_hdr]
    for row in (ip_enrol if ip_enrol else [{"gender": g} for g in ("Male", "Female", "Others")]):
        ip_data.append([
            _c(_s(row, "gender")),
            _c(_s(row, "from_state")),
            _c(_s(row, "from_other_states")),
            _c(_s(row, "nri")),
            _c(_s(row, "foreign")),
            _c(_s(row, "total")),
        ])
    integrated_body.append(_header_table(ip_data, ip_cw, _ts(
        ("GRID",     (0,0),(-1,-1),0.5,_BK),
        ("FONTNAME", (0,0),(-1, 0),"Times-Bold"),
        ("ALIGN",    (1,1),(-1,-1),"CENTER"),
    )))
    story.extend(_section_block("Integrated Programmes", integrated_body, keep_if_fits=False, min_start_height=96))

    # --- HRDC ---------------------------------------------------------------
    hrdc = _d(p.get("hrdc"))
    hrdc_rows = [
        ("Year of Establishment",                                  _s(hrdc, "year_of_establishment")),
        ("Number of UGC Orientation Programmes",                   _s(hrdc, "orientation_programmes")),
        ("Number of UGC Refresher Course",                         _s(hrdc, "refresher_courses")),
        ("Number of University's own Programmes",                  _s(hrdc, "own_programmes")),
        ("Total Number of Programmes Conducted (last five years)", _s(hrdc, "total_programmes_last_five_years")),
    ]
    story.extend(_section_block(
        "Details of UGC Human Resource Development Centre, If applicable",
        [_table([[_c(l, "CELL_B"), _c(v)] for l, v in hrdc_rows],
                [BODY_W*0.65, BODY_W*0.35], _label_col_style())],
        min_start_height=96,
    ))

    # --- Evaluative Report of Departments -----------------------------------
    dept_reports = _rows(p, "department_reports")
    dr_hdr  = [_c("Department Name", "CELL_B"), _c("Upload Report", "CELL_B")]
    dr_data = [dr_hdr]
    for row in (dept_reports if dept_reports else [{}, {}, {}]):
        dr_data.append([_c(_s(row, "department_name")), _c(_s(row, "report_reference"))])
    story.extend(_section_block("EVALUATIVE REPORT OF THE DEPARTMENTS", [_header_table(dr_data, [BODY_W*0.55, BODY_W*0.45], _ts(
        ("GRID",     (0,0),(-1,-1),0.5,_BK),
        ("FONTNAME", (0,0),(-1, 0),"Times-Bold"),
    ))], title_style="H2U", min_start_height=96))

    return story


# ---------------------------------------------------------------------------
# Section 3 - Extended Profile
# ---------------------------------------------------------------------------
YEAR_LABELS_5 = ["2019-20", "2020-21", "2021-22", "2022-23", "2023-24"]


def _metric_year_values(ep: dict, key: str) -> tuple[list[str], list[str]]:
    direct = ep.get(key)
    if isinstance(direct, dict):
        year_labels = direct.get("year_labels") or YEAR_LABELS_5
        values = direct.get("values") or [""] * len(year_labels)
    elif isinstance(direct, list):
        year_labels = ep.get("year_labels") or YEAR_LABELS_5
        values = direct
    else:
        metrics_map = _d(ep.get("metrics"))
        raw = metrics_map.get(key)
        year_labels = ep.get("year_labels") or YEAR_LABELS_5
        values = raw if isinstance(raw, list) else [""] * len(year_labels)

    if isinstance(values, dict):
        vals = [str(values.get(y, "")) for y in year_labels]
    else:
        vals = [str(v or "") for v in (values or [])]

    while len(vals) < len(year_labels):
        vals.append("")
    vals = vals[:len(year_labels)]
    return [str(y or "") for y in year_labels], vals


def _five_year_table(ep: dict, key: str, row_label: str = "Number") -> Table:
    year_labels, vals = _metric_year_values(ep, key)
    n   = len(year_labels)
    hdr = [_c("Year", "CELL_B")] + [_c(y, "CELL_B") for y in year_labels]
    vr  = [_c(row_label, "CELL_B")] + [_c(v, "CELL_C") for v in vals]
    cw  = [BODY_W * 0.16] + [BODY_W * 0.84 / n] * n
    return _header_table([hdr, vr], cw, _ts(
        ("GRID",     (0, 0), (-1, -1), 0.5, _BK),
        ("FONTNAME", (0, 0), (-1, 0),  "Times-Bold"),
        ("FONTNAME", (0, 1), (0, 1),   "Times-Bold"),
    ))


def _build_extended_profile(data: dict) -> list:
    ep = _d(data.get("extended_profile"))
    story: list = []
    story.append(PageBreak())
    story.append(_p("3. Extended Profile of the University", "H1"))
    story.append(_blank(8))

    metrics_map = _d(ep.get("metrics"))

    def single(key: str) -> str:
        return _s(ep, key) if ep.get(key) else _s(metrics_map, key)

    def metric(label: str, key: str, row_label: str = "Number") -> list:
        return _section_block(label, [_five_year_table(ep, key, row_label)], title_style="BODY", before=5, after=7, min_start_height=66)

    story.append(_p("1 Programme:", "H3"))
    story.extend(metric("1.1 Number of Programmes offered year wise for last five years", "programmes_offered"))
    dept_value = single("departments_offering_programmes")
    dept_line = "1.2 Number of departments offering academic programmes"
    if dept_value:
        dept_line = f"{dept_line}: {dept_value}"
    story.append(_p(dept_line, "BODY"))
    story.append(_blank(8))

    story.append(_p("2 Student:", "H3"))
    story.extend(metric("2.1 Number of students year wise during the last five years", "students"))
    story.extend(metric("2.2 Number of outgoing / final year students year wise during the last five years", "outgoing_students"))
    story.extend(metric("2.3 Number of students appeared in the University examination year wise during the last five years", "exam_appeared"))
    story.extend(metric("2.4 Number of revaluation applications year wise during the last 5 years", "revaluation_applications"))

    story.append(_p("3 Academic:", "H3"))
    story.extend(metric("3.1 Number of courses in all Programmes year wise during the last five years", "courses"))
    story.extend(metric("3.2 Number of full time teachers year wise during the last five years", "full_time_teachers"))
    story.extend(metric("3.3 Number of sanctioned posts year wise during the last five years", "sanctioned_posts"))

    story.append(_p("4 Institution:", "H3"))
    story.extend(metric("4.1 Number of eligible applications received for admissions to all the Programmes year wise during the last five years", "eligible_applications"))
    story.extend(metric("4.2 Number of seats earmarked for reserved category as per GOI/State Govt rule year wise during the last five years", "reserved_seats"))
    classrooms = single("total_classrooms_seminar_halls") or "________"
    computers = single("total_computers_academic") or "________"
    story.append(_p(f"4.3 Total number of classrooms and seminar halls: {classrooms}", "BODY"))
    story.append(_blank(5))
    story.append(_p(f"4.4 Total number of computers in the campus for academic purpose: {computers}", "BODY"))
    story.append(_blank(5))
    story.extend(metric("4.5 Total Expenditure excluding salary year wise during the last five years (INR in Lakhs)", "expenditure_excluding_salary", "Expenditure"))

    return story


# ---------------------------------------------------------------------------
# Section 4 - Quality Indicator Framework
# ---------------------------------------------------------------------------
def _build_qif(data: dict) -> list:
    story: list = []
    story.append(PageBreak())
    story.append(_p("4. Quality Indicator Framework (QIF)", "H1"))
    story.append(_p("Essential Note:", "H2"))
    story.append(_p("The SSR has to be filled in an online format available on the NAAC website.", "BODY"))
    story.append(_p(
        "The QIF given below presents the Metrics under each Key Indicator (KI) for all the seven Criteria.",
        "BODY",
    ))
    story.append(_blank(4))
    story.append(_p("While going through the QIF, details are given below each Metric in the form of:", "BODY"))
    for item in [
        "data required",
        "formula for calculating the information, wherever required, and",
        "File description – for uploading of document where so-ever required.",
    ]:
        story.append(_p(f"•  {item}", "BODY"))
    story.append(_blank(4))
    story.append(_p("These will help Institutions in the preparation of their SSR.", "BODY"))
    story.append(_blank(5))
    story.append(_p(
        "For some Qualitative Metrics (QlM) which seek descriptive data it is specified as to what kind "
        "of information has to be given and how much. It is advisable to keep data accordingly compiled beforehand.",
        "BODY",
    ))
    story.append(_blank(5))
    story.append(_p(
        "For the Quantitative Metrics (QnM) wherever formula is given, it must be noted that these are "
        "given merely to inform the HEIs about the manner in which data submitted will be used. That is "
        "the actual online format seeks only data in specified manner which will be processed digitally.",
        "BODY",
    ))
    story.append(_blank(5))
    story.append(_p("Metric wise weightage is also given.", "BODY"))
    story.append(_blank(8))
    story.append(_p(
        "The actual online format may change slightly from the QIF given in this Manual, in order to "
        "bring compatibility with IT design. Observe this carefully while filling up.",
        "BODY",
    ))
    return story


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def generate_ssr_pdf(
    sections_data: dict,
    generated_by: str = "",
    generated_at: "datetime | None" = None,
) -> bytes:
    """
    Build and return the SSR PDF as a bytes object.

    Args:
        sections_data: dict with keys executive_summary, university_profile,
                       extended_profile, qif.
        generated_by:  display name / email of the requesting user.
        generated_at:  UTC datetime of generation (defaults to now).
    """
    meta = {
        "generated_by": generated_by or "IQAC Administrator",
        "generated_at": generated_at or datetime.utcnow(),
    }

    buf = io.BytesIO()
    frame = Frame(
        LEFT_MARGIN, BOTTOM_MARGIN,
        PAGE_W - LEFT_MARGIN - RIGHT_MARGIN,
        PAGE_H - TOP_MARGIN - BOTTOM_MARGIN,
        id="main",
        leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0,
    )

    from reportlab.pdfgen.canvas import Canvas as _RLCanvas

    class FooterCanvas(_FooterCanvas, _RLCanvas):
        pass

    doc = BaseDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=LEFT_MARGIN,
        rightMargin=RIGHT_MARGIN,
        topMargin=TOP_MARGIN,
        bottomMargin=BOTTOM_MARGIN,
        title="NAAC Self Study Report",
        author=meta["generated_by"],
    )
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame])])

    story: list = []
    story.extend(_build_cover(sections_data, meta))
    story.extend(_build_executive_summary(sections_data))
    story.extend(_build_profile(sections_data))
    story.extend(_build_extended_profile(sections_data))
    story.extend(_build_qif(sections_data))

    doc.build(story, canvasmaker=FooterCanvas)
    return buf.getvalue()
