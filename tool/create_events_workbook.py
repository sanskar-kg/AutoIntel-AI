from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter


OUT = Path("outputs/auto_intel_ai_events/AutoIntel_AI_Events.xlsx")

EVENTS = {
    "app": [
        ("app_launch_viewed", "The app reached its usable UI and startup services began.", "Once per process launch after Firebase setup, before runApp().", "None"),
    ],
    "auth": [
        ("login_completed", "A returning user completed Truecaller sign-in.", "After auth.signIn() resolves successfully.", "method"),
        ("signup_completed", "A temporary account was created for a user who chose the fallback path.", "After auth.signInAnonymously() resolves successfully.", "method"),
    ],
    "onboarding": [
        ("onboarding_done", "The first-journey spotlight coach marks were completed or dismissed.", "When the spotlight sequence finishes or is dismissed, once per app session.", "journey"),
    ],
    "lookup": [
        ("lookup_started", "A user confirmed a paid vehicle or owner-phone lookup and the request was sent.", "Immediately before Backend.lookup() after validation, balance, and confirmation succeed.", "type"),
        ("lookup_success", "The lookup returned a result and the wallet was refreshed.", "After Backend.lookup() resolves successfully.", "type"),
        ("lookup_failed", "The lookup did not return a result.", "In the lookup exception handler after the backend rejects or the network fails.", "type, code"),
        ("insufficient_balance_shown", "The user attempted a lookup without enough wallet balance.", "When balance is below the remote-configured price before opening the recharge path.", "type"),
    ],
    "wallet": [
        ("recharge_started", "A wallet recharge order was created and checkout is about to open.", "After createOrder() succeeds and before the payment checkout is launched.", "amount_bucket, gateway"),
        ("recharge_success", "The server confirmed that the recharge succeeded.", "After checkout and order confirmation return OrderStatus.success.", "None"),
        ("recharge_failed", "The recharge could not be completed or the server marked it failed.", "On recharge exception or after order confirmation returns OrderStatus.failed.", "reason"),
    ],
    "settings": [
        ("language_changed", "The user changed the app language or restored device-default language.", "After the selected language is persisted and differs from the previous value.", "lang"),
    ],
}

PARAMETER_NOTES = {
    "method": "String: truecaller or anonymous. No account identifiers.",
    "journey": "String: spotlight. Indicates first-run coach-mark journey.",
    "type": "String: rc or phone. Never include registration numbers.",
    "code": "String: stable AppException code or unknown; no server error text.",
    "amount_bucket": "String: 0_100, 101_500, 501_1000, or 1001_plus; never send the exact amount.",
    "gateway": "String: configured payment gateway name, normalized lowercase.",
    "reason": "String: stable failure category/runtime type; never send payment or user details.",
    "lang": "String: language tag such as en, hi, or system.",
}


def style_sheet(ws, rows):
    green = "FF245D48"
    header_fill = PatternFill("solid", fgColor=green)
    header_font = Font(name="Aptos", size=11, bold=True, color="FFFFFFFF")
    body_font = Font(name="Aptos", size=10, color="FF202124")
    thin = Side(style="thin", color="FFD9E2DC")
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:D{len(rows) + 1}"
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(vertical="center", wrap_text=True)
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=1, max_col=4):
        for cell in row:
            cell.font = body_font
            cell.alignment = Alignment(vertical="top", wrap_text=True)
            cell.border = Border(bottom=thin)
    widths = [38, 66, 72, 30]
    for i, width in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = width
    ws.row_dimensions[1].height = 28
    for i in range(2, ws.max_row + 1):
        ws.row_dimensions[i].height = 44


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    index = wb.active
    index.title = "Index"
    index.append(["Flow / tab", "Event count", "Purpose"])
    for flow, rows in EVENTS.items():
        index.append([flow, len(rows), f"Events for the {flow} flow"])
    index.append(["parameter_dictionary", len(PARAMETER_NOTES), "Parameter definitions and privacy rules"])
    style_sheet(index, list(index.iter_rows(values_only=True)))
    index.column_dimensions["A"].width = 30
    index.column_dimensions["B"].width = 16
    index.column_dimensions["C"].width = 62
    index.auto_filter.ref = f"A1:C{index.max_row}"

    for flow, events in EVENTS.items():
        ws = wb.create_sheet(flow)
        ws.append(["Event name", "Description", "Trigger", "Parameters"])
        for event in events:
            ws.append(event)
        style_sheet(ws, events)

    ws = wb.create_sheet("parameter_dictionary")
    ws.append(["Parameter", "Definition / allowed values", "Privacy rule", "Used by"])
    for name, definition in PARAMETER_NOTES.items():
        used_by = ", ".join(event[0] for events in EVENTS.values() for event in events if name in event[3])
        ws.append([name, definition, "Do not send PII, registration numbers, names, phone numbers, or raw payment details.", used_by])
    style_sheet(ws, list(ws.iter_rows(values_only=True)))
    ws.column_dimensions["A"].width = 22
    ws.column_dimensions["B"].width = 70
    ws.column_dimensions["C"].width = 70
    ws.column_dimensions["D"].width = 70

    wb.properties.title = "AutoIntel AI Analytics Events"
    wb.properties.subject = "Firebase Analytics event catalogue and implementation reference"
    wb.properties.creator = "AutoIntel AI"
    wb.save(OUT)
    print(OUT.resolve())


if __name__ == "__main__":
    main()
