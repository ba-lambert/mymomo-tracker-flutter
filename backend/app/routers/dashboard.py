from datetime import datetime, time
from typing import Optional

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from .. import repository
from ..database import get_db

router = APIRouter(tags=["dashboard"])
templates = Jinja2Templates(directory="app/templates")


@router.get("/", response_class=HTMLResponse)
def dashboard_home(request: Request, db: Session = Depends(get_db)):
    phones = repository.list_phones_with_counts(db)
    total_messages = sum(phone.message_count for phone in phones)
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "phones": phones,
            "total_messages": total_messages,
        },
    )


@router.get("/phones/{phone_id}", response_class=HTMLResponse)
def phone_detail(
    request: Request,
    phone_id: int,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
    source: Optional[str] = None,
    db: Session = Depends(get_db),
):
    phone = repository.get_phone(db, phone_id)
    if phone is None:
        return HTMLResponse("Phone not found", status_code=404)

    # A plain "To" date (no time of day) means "through the end of that
    # day" to anyone picking it, but compares as that day's midnight,
    # excluding everything but messages at exactly 00:00:00. Treat a
    # midnight end as end-of-day so the picked day is fully included.
    if end is not None and end.time() == time.min:
        end = end.replace(hour=23, minute=59, second=59, microsecond=999999)

    all_messages = repository.list_messages(db, phone_id, start, end)
    messages = [m for m in all_messages if source is None or m.source == source]
    total_in = sum(m.amount for m in messages if m.is_incoming)
    total_out = sum(m.amount for m in messages if not m.is_incoming)
    sender_groups = repository.group_by_sender(messages)

    sms_count = sum(1 for m in all_messages if m.source == "sms")
    whatsapp_count = sum(1 for m in all_messages if m.source == "whatsapp")
    pull_requests = repository.list_pull_requests(db, phone_id)

    now = datetime.now()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    return templates.TemplateResponse(
        "phone_detail.html",
        {
            "request": request,
            "phone": phone,
            "messages": messages,
            "sender_groups": sender_groups,
            "total_in": total_in,
            "total_out": total_out,
            "start": start,
            "end": end,
            "source": source,
            "sms_count": sms_count,
            "whatsapp_count": whatsapp_count,
            "pull_requests": pull_requests,
            "month_start": month_start.strftime("%Y-%m-%d"),
            "month_end": now.strftime("%Y-%m-%d"),
        },
    )


@router.post("/phones/{phone_id}/pull-requests")
def request_pull(
    phone_id: int,
    start: str = Form(default=""),
    end: str = Form(default=""),
    db: Session = Depends(get_db),
):
    """Queues an export request for the phone's background task to pick up
    next time it checks in, then redirects back to the phone's page."""
    phone = repository.get_phone(db, phone_id)
    if phone is None:
        return HTMLResponse("Phone not found", status_code=404)

    start_date = datetime.fromisoformat(start) if start else None
    end_date = datetime.fromisoformat(end) if end else None
    repository.create_pull_request(db, phone, start_date, end_date)
    return RedirectResponse(url=f"/phones/{phone_id}", status_code=303)


@router.post("/phones/{phone_id}/delete")
def delete_phone(phone_id: int, db: Session = Depends(get_db)):
    phone = repository.get_phone(db, phone_id)
    if phone is not None:
        repository.delete_phone(db, phone)
    return RedirectResponse(url="/", status_code=303)
