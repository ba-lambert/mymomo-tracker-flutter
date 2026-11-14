import re
from dataclasses import dataclass
from typing import Optional

_AMOUNT_RE = re.compile(r"(\d[\d,]*(?:\.\d+)?)\s*RWF")
_REFERENCE_RE = re.compile(r"(?:TxId|Ref(?:erence)?|Financial\s*Transaction\s*Id)\s*[:.]?\s*(\d{6,})", re.IGNORECASE)

_RECEIVED_RE = re.compile(r"received\s+[\d,.]+\s*RWF\s+from\s+(.+?)(?:\s*\(|\s+at\s+\d|\.)", re.IGNORECASE)
_PAYMENT_RE = re.compile(r"payment of\s+[\d,.]+\s*RWF\s+to\s+(.+?)(?:\s+was\s+completed|\.)", re.IGNORECASE)
_TRANSFER_RE = re.compile(r"[\d,.]+\s*RWF\s+transferred\s+to\s+(.+?)(?:\s*\(|\.)", re.IGNORECASE)
_WITHDRAW_RE = re.compile(r"withdr\w+\s+[\d,.]+\s*RWF.*?(?:from|at)\s+(.+?)(?:\s+was\s+completed|\.|$)", re.IGNORECASE)
_PURCHASE_RE = re.compile(r"transaction of\s+[\d,.]+\s*RWF\s+by\s+(.+?)(?:\s+was\s+completed|\.|$)", re.IGNORECASE)
_BANK_DEPOSIT_RE = re.compile(r"bank deposit of\s+[\d,.]+\s*RWF", re.IGNORECASE)
_SELF_TRANSFER_RE = re.compile(r"you have transferred\s+[\d,.]+\s*RWF\s+to\s+(.+?)(?:\s*\(|\.)", re.IGNORECASE)
_NOT_SETTLED_RE = re.compile(r"\b(?:has failed|was canceled|was cancelled|is rejected|was reversed)\b", re.IGNORECASE)


@dataclass
class ParsedMessage:
    amount: float
    is_incoming: bool
    transaction_type: str
    description: str
    reference: Optional[str]


def _extract_amount(body: str) -> float:
    match = _AMOUNT_RE.search(body)
    if match is None:
        return 0.0
    return float(match.group(1).replace(",", ""))


def _extract_reference(body: str) -> Optional[str]:
    match = _REFERENCE_RE.search(body)
    return match.group(1) if match else None


def parse_message(body: str) -> ParsedMessage:
    """Extracts amount, direction, category, counterparty and reference from a MoMo SMS body.

    MTN MoMo messages follow a handful of fixed templates (received, payment,
    transfer, withdrawal, airtime/bundle purchase); this matches each one and
    falls back to the raw body when none apply.

    @param body - Raw SMS text as exported from the phone.
    @returns Parsed amount, direction, category, a short human description, and the transaction reference if present.
    """
    reference = _extract_reference(body)

    if _NOT_SETTLED_RE.search(body):
        # Failed/canceled/reversed notices mention an amount but no money moved.
        return ParsedMessage(0.0, False, "other", body.split(".")[0][:80], reference)

    amount = _extract_amount(body)

    if match := _RECEIVED_RE.search(body):
        return ParsedMessage(amount, True, "received", f"From {match.group(1).strip()}", reference)

    if _BANK_DEPOSIT_RE.search(body):
        return ParsedMessage(amount, True, "received", "Bank deposit", reference)

    if match := _PAYMENT_RE.search(body):
        return ParsedMessage(amount, False, "payment", f"To {match.group(1).strip()}", reference)

    if match := _SELF_TRANSFER_RE.search(body):
        return ParsedMessage(amount, False, "transfer", f"To {match.group(1).strip()}", reference)

    if match := _TRANSFER_RE.search(body):
        return ParsedMessage(amount, False, "transfer", f"To {match.group(1).strip()}", reference)

    if match := _WITHDRAW_RE.search(body):
        return ParsedMessage(amount, False, "withdrawal", f"At {match.group(1).strip()}", reference)

    if match := _PURCHASE_RE.search(body):
        return ParsedMessage(amount, False, "purchase", f"By {match.group(1).strip()}", reference)

    is_incoming = "received" in body.lower()
    return ParsedMessage(amount, is_incoming, "other", body.split(".")[0][:80], reference)
