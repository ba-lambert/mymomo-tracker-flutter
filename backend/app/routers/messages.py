import json
import re
import zipfile
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session

from .. import repository, schemas
from ..database import get_db

router = APIRouter(prefix="/api", tags=["messages"])

UPLOADS_DIR = Path(__file__).resolve().parent.parent.parent / "uploads"


def _save_upload_copy(phone_name: str, payload: dict) -> None:
    """Writes an uncompressed copy of a received upload batch to the uploads folder.

    Kept alongside the database insert so raw exports stay available for
    inspection or replay even if the database is reset.

    @param phone_name - Name of the phone the batch came from, used in the file name.
    @param payload - JSON-serializable upload content to store as-is.
    """
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", phone_name) or "unknown"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    target = UPLOADS_DIR / f"{safe_name}_{timestamp}.json"
    target.write_text(json.dumps(payload, indent=2, default=str))


@router.post("/messages/upload", response_model=schemas.UploadResult)
def upload_messages(payload: schemas.UploadRequest, db: Session = Depends(get_db)):
    """Stores a batch of exported SMS for a phone, creating the phone if needed."""
    phone = repository.register_phone(db, payload.phone_name.strip())
    _save_upload_copy(phone.name, payload.model_dump())
    inserted, skipped = repository.insert_messages(db, phone, payload.messages)
    return schemas.UploadResult(
        phone_name=phone.name,
        received=len(payload.messages),
        inserted=inserted,
        skipped_duplicates=skipped,
    )


@router.post("/messages/upload-zip", response_model=schemas.UploadResult)
def upload_messages_zip(
    phone_name: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """Stores a zip export (app's `ExportService` output) for a phone.

    The zip must contain a `messages.json` with a `groups` map of
    `{sender_phone_number: [{address, body, date}, ...]}`.
    """
    try:
        with zipfile.ZipFile(BytesIO(file.file.read())) as archive:
            raw = archive.read("messages.json")
    except (zipfile.BadZipFile, KeyError) as exc:
        raise HTTPException(
            status_code=400, detail=f"Invalid export zip: {exc}"
        ) from exc

    payload = json.loads(raw)
    groups: dict[str, list[dict]] = payload.get("groups", {})

    _save_upload_copy(phone_name.strip(), payload)

    messages = [
        schemas.MessageIn(
            sender=sender,
            contact_name=item.get("contact_name"),
            body=item["body"],
            date=item["date"],
        )
        for sender, items in groups.items()
        for item in items
    ]

    phone = repository.register_phone(db, phone_name.strip())
    inserted, skipped = repository.insert_messages(db, phone, messages)
    return schemas.UploadResult(
        phone_name=phone.name,
        received=len(messages),
        inserted=inserted,
        skipped_duplicates=skipped,
    )


@router.get("/phones/{phone_id}/messages", response_model=list[schemas.MessageOut])
def get_phone_messages(
    phone_id: int,
    start: Optional[datetime] = Query(default=None),
    end: Optional[datetime] = Query(default=None),
    db: Session = Depends(get_db),
):
    phone = repository.get_phone(db, phone_id)
    if phone is None:
        raise HTTPException(status_code=404, detail="Phone not found")
    return repository.list_messages(db, phone_id, start, end)
