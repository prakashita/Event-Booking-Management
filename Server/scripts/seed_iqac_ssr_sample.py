"""
IQAC SSR Sample Data Seeder
============================
Inserts / updates one complete IQAC SSR dataset for Vidyashilp University
so that the PDF and Word export functions show fully populated tables.

Usage (from project root):
    python Server/scripts/seed_iqac_ssr_sample.py

Or from Server/ directory:
    python scripts/seed_iqac_ssr_sample.py

Uses the same MONGODB_URL / DB_NAME env vars as the main app.
No beanie required – uses motor directly with a raw upsert.
"""
from __future__ import annotations

import asyncio
import os
import sys
from datetime import datetime, timezone

# ── allow running from project root or from Server/ ──────────────────────────
_HERE = os.path.dirname(os.path.abspath(__file__))
_SERVER = os.path.dirname(_HERE)
if _SERVER not in sys.path:
    sys.path.insert(0, _SERVER)

from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient

load_dotenv(os.path.join(_SERVER, ".env"))

# ── connection ────────────────────────────────────────────────────────────────
MONGODB_URL = os.getenv("MONGODB_URL") or os.getenv("DATABASE_URL") or "mongodb://localhost:27017/eventdb"
DB_NAME     = os.getenv("DB_NAME", "eventdb")

COLLECTION  = "iqac_ssr_sections"
SEEDER_USER = "seed_script"
SEEDER_NAME = "Sample Data Seeder"
NOW         = datetime.now(tz=timezone.utc)

# ── helper ────────────────────────────────────────────────────────────────────
YEAR_LABELS = ["2019-20", "2020-21", "2021-22", "2022-23", "2023-24"]


# =============================================================================
# Section 1 – Executive Summary
# =============================================================================
EXECUTIVE_SUMMARY = {
    "introductory_note": (
        "Vidyashilp University (VSU), established in 2012 under the Karnataka Private "
        "Universities Establishment Act, is a self-financing private university located in "
        "Yelahanka, North Bengaluru. The university envisions becoming a centre of excellence "
        "in liberal arts, sciences, engineering, and management education. Its mission is to "
        "nurture holistic, career-ready graduates who are ethically grounded and globally "
        "competitive. Spread across a 52-acre green campus, VSU houses 8 schools, 42 academic "
        "departments, and over 6,200 students across UG, PG, and doctoral programmes. "
        "The institution places strong emphasis on outcome-based education, industry-academia "
        "collaboration, research, and community engagement."
    ),
    "criteria_summary": (
        "Criterion I – Curricular Aspects: VSU offers 94 programmes spanning Arts, Science, "
        "Commerce, Engineering, Management and Law. Curriculum revision is undertaken every "
        "two years with active BoS participation. Industry-aligned electives and skill-based "
        "courses constitute 20% of total credits.\n\n"
        "Criterion II – Teaching-Learning & Evaluation: The university follows an outcome-based "
        "education model with continuous internal assessment (CIA) and end-semester "
        "examinations. ICT-enabled classrooms and a learning management system (LMS) support "
        "blended learning. Student-teacher ratio is 18:1.\n\n"
        "Criterion III – Research, Innovations & Extension: VSU has 12 active research centres "
        "and published 487 Scopus-indexed papers over the last five years. The university "
        "received ₹8.4 Cr in research funding. The NSS and NCC units have logged over 15,000 "
        "community service hours annually.\n\n"
        "Criterion IV – Infrastructure & Learning Resources: The campus has 148 smart "
        "classrooms, a 1.2-lakh sq.ft. central library with 85,000+ volumes, and 8 "
        "specialised computing labs with 1,240 systems. High-speed 1 Gbps internet is "
        "available campus-wide.\n\n"
        "Criterion V – Student Support & Progression: VSU provides merit-cum-means "
        "scholarships, career counselling, and a full-time placement cell. Placement rate "
        "for UG engineering graduates stands at 82%. The alumni network covers 18 countries.\n\n"
        "Criterion VI – Governance, Leadership & Management: The university is governed by a "
        "statutory Board of Management and Academic Council. All key processes are ISO "
        "9001:2015 certified. Internal Quality Assurance Cell (IQAC) was constituted in 2015 "
        "and has conducted 18 quality enhancement workshops.\n\n"
        "Criterion VII – Institutional Values & Best Practices: VSU promotes gender equity "
        "through a vibrant Women's Cell and Grievance Redressal Forum. The green campus "
        "initiative has reduced carbon footprint by 22% since 2018 through solar power "
        "(650 kWp) and rainwater harvesting."
    ),
    "swoc_analysis": (
        "Strengths:\n"
        "• Well-established undergraduate and postgraduate programmes with high enrolment.\n"
        "• Strong industry-academia partnerships with 120+ MoUs.\n"
        "• Competent and qualified faculty with 68% PhD holders.\n"
        "• Modern infrastructure including smart classrooms and research labs.\n\n"
        "Weaknesses:\n"
        "• Limited funded research projects at national/international level.\n"
        "• Need to strengthen e-content creation by faculty.\n"
        "• Alumni engagement in academic activities requires enhancement.\n\n"
        "Opportunities:\n"
        "• NEP 2020 implementation offers scope for flexible multi-disciplinary programmes.\n"
        "• Growing demand for technology-enabled, skill-based education.\n"
        "• Scope for international collaborations and twinning programmes.\n\n"
        "Challenges:\n"
        "• Retaining highly qualified faculty in a competitive urban market.\n"
        "• Adapting rapidly to technological changes in pedagogy.\n"
        "• Sustaining quality standards with increasing student intake."
    ),
    "additional_information": (
        "VSU is a member of the Association of Indian Universities (AIU) and the "
        "Association of Commonwealth Universities (ACU). The university hosts a dedicated "
        "Center for Innovation and Entrepreneurship (CIE) and a Technology Business Incubator "
        "supported by DST-NSTEDB. An ISO 50001-certified energy management system is in place. "
        "The university also runs a 200-bed student hostel complex with separate facilities "
        "for men and women."
    ),
    "conclusive_explication": (
        "Vidyashilp University has consistently demonstrated its commitment to quality "
        "education, research, and social responsibility. The institution's focused growth "
        "strategy, investment in infrastructure, and emphasis on outcome-based education "
        "position it well for national and international accreditation. The IQAC, through "
        "systematic quality audits and stakeholder feedback mechanisms, ensures continuous "
        "improvement. The university is well poised to achieve its vision of becoming a "
        "globally recognised institution of excellence."
    ),
}

# =============================================================================
# Section 2 – University Profile
# =============================================================================
UNIVERSITY_PROFILE = {
    "basic_information": {
        "name":    "Vidyashilp University",
        "address": "Yelahanka New Town, Doddaballapur Road",
        "city":    "Bengaluru",
        "pin":     "560064",
        "state":   "Karnataka",
        "website": "https://www.vidyashilp.edu.in",
    },
    "contacts": [
        {
            "designation": "Vice Chancellor",
            "name":        "Prof. Ramesh Kumar Nair",
            "telephone":   "080-28465000",
            "mobile":      "9845012345",
            "fax":         "080-28465001",
            "email":       "vc@vidyashilp.edu.in",
        },
        {
            "designation": "IQAC Coordinator",
            "name":        "Dr. Savitha M. Rao",
            "telephone":   "080-28465020",
            "mobile":      "9741023456",
            "fax":         "",
            "email":       "iqac@vidyashilp.edu.in",
        },
        {
            "designation": "Registrar",
            "name":        "Dr. K. Subramaniam",
            "telephone":   "080-28465010",
            "mobile":      "9880198765",
            "fax":         "080-28465011",
            "email":       "registrar@vidyashilp.edu.in",
        },
    ],
    "institution": {
        "nature": "Private",
        "status": "Deemed to be University (Under Section 3 of UGC Act 1956)",
        "type":   "Co-Educational",
    },
    "establishment": {
        "establishment_date":                  "15/07/2012",
        "status_prior":                        "Autonomous",
        "establishment_date_if_applicable":    "12/06/2009",
    },
    "recognition": {
        "ugc_2f_date":  "20/08/2012",
        "ugc_12b_date": "20/08/2012",
        "other_agencies": [
            {"agency": "AICTE (Engineering & Technology)", "recognition": "Approved"},
            {"agency": "BCI (Law)", "recognition": "Approved"},
            {"agency": "PCI (Pharmacy)", "recognition": "Approved"},
        ],
    },
    "upe_recognized": "No",
    "campuses": [
        {
            "campus_type":         "Main Campus",
            "address":             "Yelahanka New Town, Doddaballapur Road, Bengaluru – 560064",
            "location":            "Semi Urban",
            "campus_area_acres":   "52.0",
            "built_up_area_sq_mts":"58,420",
            "programmes_offered":  "UG, PG, Ph.D.",
            "establishment_date":  "15/07/2012",
            "recognition_date":    "20/08/2012",
        },
        {
            "campus_type":         "Off-Campus Centre",
            "address":             "Rajajinagar, Bengaluru – 560010",
            "location":            "Urban",
            "campus_area_acres":   "3.5",
            "built_up_area_sq_mts":"8,200",
            "programmes_offered":  "PG (Management)",
            "establishment_date":  "01/06/2018",
            "recognition_date":    "10/08/2018",
        },
    ],
    "academic_information": {
        "affiliated_institutions": [],   # Not applicable (deemed university)
        "college_type_affiliations": [], # Not applicable
        "college_details": [
            {"label": "Constituent Colleges",                               "value": "8"},
            {"label": "Affiliated Colleges",                                "value": "0"},
            {"label": "Colleges Under 2(f)",                                "value": "0"},
            {"label": "Colleges Under 2(f) and 12B",                       "value": "0"},
            {"label": "NAAC Accredited Colleges",                           "value": "0"},
            {"label": "Colleges with Potential for Excellence (UGC)",       "value": "0"},
            {"label": "Autonomous Colleges",                                "value": "0"},
            {"label": "Colleges with Postgraduate Departments",             "value": "8"},
            {"label": "Colleges with Research Departments",                 "value": "6"},
            {"label": "University Recognized Research Institutes/Centers",  "value": "12"},
        ],
        "sra_recognized": "Yes",
    },
    "staff": {
        "teaching": [
            {
                "status":                        "Sanctioned",
                "Professor_Male":                "18", "Professor_Female":          "8",  "Professor_Others": "0", "Professor_Total":            "26",
                "Associate Professor_Male":       "32", "Associate Professor_Female": "20", "Associate Professor_Others": "0", "Associate Professor_Total":  "52",
                "Assistant Professor_Male":       "60", "Assistant Professor_Female": "54", "Assistant Professor_Others": "0", "Assistant Professor_Total":  "114",
                "Total":                         "192",
            },
            {
                "status":                        "Recruited",
                "Professor_Male":                "16", "Professor_Female":          "7",  "Professor_Others": "0", "Professor_Total":            "23",
                "Associate Professor_Male":       "28", "Associate Professor_Female": "18", "Associate Professor_Others": "0", "Associate Professor_Total":  "46",
                "Assistant Professor_Male":       "55", "Assistant Professor_Female": "50", "Assistant Professor_Others": "1", "Assistant Professor_Total":  "106",
                "Total":                         "175",
            },
            {
                "status":                        "Yet to Recruit",
                "Professor_Male":                "2",  "Professor_Female":          "1",  "Professor_Others": "0", "Professor_Total":            "3",
                "Associate Professor_Male":       "4",  "Associate Professor_Female": "2",  "Associate Professor_Others": "0", "Associate Professor_Total":  "6",
                "Assistant Professor_Male":       "5",  "Assistant Professor_Female": "4",  "Assistant Professor_Others": "0", "Assistant Professor_Total":  "9",
                "Total":                         "18",
            },
            {
                "status":                        "On Contract",
                "Professor_Male":                "0",  "Professor_Female":          "0",  "Professor_Others": "0", "Professor_Total":            "0",
                "Associate Professor_Male":       "2",  "Associate Professor_Female": "1",  "Associate Professor_Others": "0", "Associate Professor_Total":  "3",
                "Assistant Professor_Male":       "8",  "Assistant Professor_Female": "6",  "Assistant Professor_Others": "0", "Assistant Professor_Total":  "14",
                "Total":                         "17",
            },
        ],
        "non_teaching": [
            {"status": "Sanctioned",    "Male": "48",  "Female": "32", "Others": "0", "Total": "80"},
            {"status": "Recruited",     "Male": "42",  "Female": "28", "Others": "0", "Total": "70"},
            {"status": "Yet to Recruit","Male": "6",   "Female": "4",  "Others": "0", "Total": "10"},
            {"status": "On Contract",   "Male": "12",  "Female": "8",  "Others": "0", "Total": "20"},
        ],
        "technical": [
            {"status": "Sanctioned",    "Male": "30",  "Female": "10", "Others": "0", "Total": "40"},
            {"status": "Recruited",     "Male": "26",  "Female": "9",  "Others": "0", "Total": "35"},
            {"status": "Yet to Recruit","Male": "4",   "Female": "1",  "Others": "0", "Total": "5"},
            {"status": "On Contract",   "Male": "5",   "Female": "2",  "Others": "0", "Total": "7"},
        ],
    },
    "qualification_details": {
        "permanent_teachers": [
            {
                "qualification":                 "D.sc/D.Litt",
                "Professor_Male": "2",  "Professor_Female": "1",  "Professor_Others": "0",
                "Associate Professor_Male": "0", "Associate Professor_Female": "0", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "0", "Assistant Professor_Female": "0", "Assistant Professor_Others": "0",
                "Total": "3",
            },
            {
                "qualification":                 "Ph.D.",
                "Professor_Male": "14", "Professor_Female": "6",  "Professor_Others": "0",
                "Associate Professor_Male": "20","Associate Professor_Female": "12","Associate Professor_Others": "0",
                "Assistant Professor_Male": "28","Assistant Professor_Female": "26","Assistant Professor_Others": "1",
                "Total": "107",
            },
            {
                "qualification":                 "M.Phil.",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "4", "Associate Professor_Female": "3", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "12","Assistant Professor_Female": "10","Assistant Professor_Others": "0",
                "Total": "29",
            },
            {
                "qualification":                 "PG",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "4", "Associate Professor_Female": "3", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "15","Assistant Professor_Female": "14","Assistant Professor_Others": "0",
                "Total": "36",
            },
        ],
        "temporary_teachers": [
            {
                "qualification":                 "Ph.D.",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "2", "Associate Professor_Female": "1", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "4", "Assistant Professor_Female": "3", "Assistant Professor_Others": "0",
                "Total": "10",
            },
            {
                "qualification":                 "PG",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "0", "Associate Professor_Female": "0", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "6", "Assistant Professor_Female": "8", "Assistant Professor_Others": "0",
                "Total": "14",
            },
        ],
        "part_time_teachers": [
            {
                "qualification":                 "Ph.D.",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "0", "Associate Professor_Female": "0", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "2", "Assistant Professor_Female": "1", "Assistant Professor_Others": "0",
                "Total": "3",
            },
            {
                "qualification":                 "PG",
                "Professor_Male": "0",  "Professor_Female": "0",  "Professor_Others": "0",
                "Associate Professor_Male": "0", "Associate Professor_Female": "0", "Associate Professor_Others": "0",
                "Assistant Professor_Male": "4", "Assistant Professor_Female": "3", "Assistant Professor_Others": "0",
                "Total": "7",
            },
        ],
    },
    "distinguished_academicians": [
        {"role": "Emeritus Professor",  "male": "3",  "female": "1", "others": "0", "total": "4"},
        {"role": "Adjunct Professor",   "male": "8",  "female": "4", "others": "0", "total": "12"},
        {"role": "Visiting Professor",  "male": "14", "female": "6", "others": "0", "total": "20"},
    ],
    "chairs": [
        {
            "department": "School of Management",
            "chair":      "Infosys Chair in Business Innovation",
            "sponsor":    "Infosys Foundation, Bengaluru",
        },
        {
            "department": "School of Engineering",
            "chair":      "Wipro Chair in Sustainable Technologies",
            "sponsor":    "Wipro Ltd., Bengaluru",
        },
        {
            "department": "School of Life Sciences",
            "chair":      "Biocon Chair in Biosciences",
            "sponsor":    "Biocon Ltd., Bengaluru",
        },
    ],
    "student_enrolment": [
        # UG
        {"programme": "UG", "gender": "Male",   "from_state": "2,240", "from_other_states": "380", "nri": "12", "foreign": "4",  "total": "2,636"},
        {"programme": "UG", "gender": "Female", "from_state": "2,060", "from_other_states": "290", "nri": "10", "foreign": "2",  "total": "2,362"},
        {"programme": "UG", "gender": "Others", "from_state": "6",     "from_other_states": "0",   "nri": "0",  "foreign": "0",  "total": "6"},
        # PG
        {"programme": "PG", "gender": "Male",   "from_state": "520",  "from_other_states": "180", "nri": "5",  "foreign": "2",  "total": "707"},
        {"programme": "PG", "gender": "Female", "from_state": "480",  "from_other_states": "140", "nri": "4",  "foreign": "1",  "total": "625"},
        {"programme": "PG", "gender": "Others", "from_state": "2",    "from_other_states": "0",   "nri": "0",  "foreign": "0",  "total": "2"},
        # Ph.D.
        {
            "programme": "PG Diploma recognized by statutory authority\nincluding university",
            "gender": "Male",   "from_state": "45",  "from_other_states": "30", "nri": "2",  "foreign": "1",  "total": "78",
        },
        {
            "programme": "",
            "gender": "Female", "from_state": "35",  "from_other_states": "20", "nri": "1",  "foreign": "0",  "total": "56",
        },
        {
            "programme": "",
            "gender": "Others", "from_state": "0",   "from_other_states": "0",  "nri": "0",  "foreign": "0",  "total": "0",
        },
    ],
    "integrated_programmes": {
        "offered":            "Yes",
        "total_programmes":   "4",
        "enrolment": [
            {"gender": "Male",   "from_state": "120", "from_other_states": "40", "nri": "2", "foreign": "1", "total": "163"},
            {"gender": "Female", "from_state": "105", "from_other_states": "30", "nri": "1", "foreign": "0", "total": "136"},
            {"gender": "Others", "from_state": "0",   "from_other_states": "0",  "nri": "0", "foreign": "0", "total": "0"},
        ],
    },
    "hrdc": {
        "year_of_establishment":           "2015",
        "orientation_programmes":          "12",
        "refresher_courses":               "18",
        "own_programmes":                  "24",
        "total_programmes_last_five_years": "54",
    },
    "department_reports": [
        {"department_name": "School of Engineering & Technology",       "report_reference": ""},
        {"department_name": "School of Management Studies",             "report_reference": ""},
        {"department_name": "School of Sciences",                       "report_reference": ""},
        {"department_name": "School of Arts & Humanities",              "report_reference": ""},
        {"department_name": "School of Law",                            "report_reference": ""},
        {"department_name": "School of Commerce & Finance",             "report_reference": ""},
        {"department_name": "School of Education",                      "report_reference": ""},
        {"department_name": "School of Health Sciences",                "report_reference": ""},
    ],
}

# =============================================================================
# Section 3 – Extended Profile
# =============================================================================
# The frontend stores metrics under data.metrics as plain 5-element arrays.
# Single-value fields live at the top level alongside year_labels.
EXTENDED_PROFILE = {
    "year_labels": YEAR_LABELS,

    # Single-value fields (read directly by the UI)
    "departments_offering_programmes": "42",
    "total_classrooms_seminar_halls":  "148",
    "total_computers_academic":        "1240",

    # All five-year metrics live under "metrics" as plain string arrays
    "metrics": {
        # 3.1 Programme
        "programmes_offered":            ["72", "78", "86", "90", "94"],

        # 3.2 Student
        "students":                      ["4820", "5100", "5480", "5860", "6215"],
        "outgoing_students":             ["1040", "1120", "1220", "1300", "1385"],
        "exam_appeared":                 ["4650", "4920", "5290", "5680", "6050"],
        "revaluation_applications":      ["380",  "420",  "460",  "510",  "540"],

        # 3.3 Academic
        "courses":                       ["1840", "1980", "2120", "2240", "2380"],
        "full_time_teachers":            ["148",  "155",  "162",  "170",  "175"],
        "sanctioned_posts":              ["180",  "185",  "188",  "192",  "192"],

        # 3.4 Institution
        "eligible_applications":         ["8200", "8900", "9400", "10100", "10800"],
        "reserved_seats":                ["960",  "1020", "1080", "1140",  "1200"],
        "expenditure_excluding_salary":  ["1240", "1380", "1520", "1680",  "1840"],
    },
}

# =============================================================================
# Section 4 – QIF
# =============================================================================
QIF = {
    "preparation_notes": (
        "The Quality Indicator Framework (QIF) data for Vidyashilp University has been "
        "compiled from verified institutional records including academic registers, finance "
        "accounts, library management system, examination cell data, HR records, and "
        "research cell reports.\n"
        "All supporting documents have been uploaded to the NAAC online portal as per the "
        "prescribed format. Qualitative metrics are supported by 500-word write-ups where "
        "applicable. The IQAC has coordinated data collection from all 8 schools and 42 "
        "departments to ensure accuracy and completeness of the submitted data."
    ),
}

# =============================================================================
# Seed data registry
# =============================================================================
SECTIONS: list[tuple[str, dict]] = [
    ("executive_summary",  EXECUTIVE_SUMMARY),
    ("university_profile", UNIVERSITY_PROFILE),
    ("extended_profile",   EXTENDED_PROFILE),
    ("qif",                QIF),
]


# =============================================================================
# Main async seeder
# =============================================================================
async def seed() -> None:
    client = AsyncIOMotorClient(MONGODB_URL)
    db     = client[DB_NAME]
    coll   = db[COLLECTION]

    print(f"Connecting to: {DB_NAME} / {COLLECTION}")
    print(f"Seeding {len(SECTIONS)} SSR sections …\n")

    for section_key, data in SECTIONS:
        doc = {
            "$set": {
                "section_key":      section_key,
                "data":             data,
                "updated_by":       SEEDER_USER,
                "updated_by_name":  SEEDER_NAME,
                "updated_by_email": "",
                "updated_at":       NOW,
            },
            "$setOnInsert": {
                "created_by":      SEEDER_USER,
                "created_by_name": SEEDER_NAME,
                "created_at":      NOW,
            },
        }
        result = await coll.update_one(
            {"section_key": section_key},
            doc,
            upsert=True,
        )

        if result.upserted_id:
            action = "inserted"
        elif result.modified_count:
            action = "updated"
        else:
            action = "unchanged"

        print(f"  [{action:9s}]  {section_key}")

    client.close()
    print("\nDone. Run the PDF/Word export to verify populated tables.")


if __name__ == "__main__":
    asyncio.run(seed())
