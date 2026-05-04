import os
import sys
import unittest
from datetime import datetime
from io import BytesIO


sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from docx import Document

from ssr_docx import generate_ssr_docx
from ssr_pdf import generate_ssr_pdf, _yes_no_marks


class TestSsrPdfLayout(unittest.TestCase):
    def test_generates_pdf_with_long_dynamic_tables(self):
        long_text = (
            "University with Potential for Excellence and a long descriptive "
            "value that should wrap naturally without clipping or overlap. "
        )
        sections = {
            "executive_summary": {"introductory_note": long_text * 4},
            "university_profile": {
                "basic_information": {
                    "name": "Example University",
                    "address": long_text * 2,
                    "city": "Hyderabad",
                    "pin": "500001",
                    "state": "Telangana",
                    "website": "https://example.edu",
                },
                "contacts": [
                    {
                        "designation": "Vice Chancellor",
                        "name": long_text,
                        "telephone": "040-123456",
                        "mobile": "9999999999",
                        "email": "vc@example.edu",
                    }
                ],
                "campuses": [
                    {
                        "campus_type": "Main",
                        "address": long_text,
                        "location": "Urban",
                        "campus_area_acres": "100",
                        "built_up_area_sq_mts": "50000",
                        "programmes_offered": long_text,
                        "establishment_date": "2000",
                        "recognition_date": "2001",
                    }
                    for _ in range(12)
                ],
                "student_enrolment": [
                    {
                        "programme": "PG",
                        "gender": gender,
                        "from_state": "10",
                        "from_other_states": "20",
                        "nri": "1",
                        "foreign": "2",
                        "total": "33",
                    }
                    for gender in ("Male", "Female", "Others") * 10
                ],
            },
            "extended_profile": {},
            "qif": {},
        }

        pdf = generate_ssr_pdf(
            sections,
            generated_by="layout-test",
            generated_at=datetime(2026, 5, 2),
        )

        self.assertGreater(len(pdf), 10_000)
        self.assertTrue(pdf.startswith(b"%PDF-"))

    def test_yes_no_marks_do_not_default_blank_to_no(self):
        self.assertEqual(_yes_no_marks("Yes"), ("X", ""))
        self.assertEqual(_yes_no_marks("No"), ("", "X"))
        self.assertEqual(_yes_no_marks(""), ("", ""))

    def test_docx_export_uses_corrected_layout(self):
        sections = {
            "executive_summary": {},
            "university_profile": {
                "upe_recognized": "",
                "academic_information": {"sra_recognized": "No"},
                "integrated_programmes": {"offered": "No"},
                "qualification_details": {},
            },
            "extended_profile": {"year_labels": ["", "", "", "", ""], "metrics": {}},
            "qif": {"notes": "This saved QIF text should not be exported."},
        }

        blob = generate_ssr_docx(
            sections,
            generated_by="layout-test",
            generated_at=datetime(2026, 5, 2),
        )
        doc = Document(BytesIO(blob))
        text = "\n".join(p.text for p in doc.paragraphs)

        self.assertIn("3. Extended Profile of the University", text)
        self.assertIn("4. Quality Indicator Framework (QIF)", text)
        self.assertIn("data required", text)
        self.assertNotIn("This saved QIF text should not be exported.", text)


if __name__ == "__main__":
    unittest.main()
