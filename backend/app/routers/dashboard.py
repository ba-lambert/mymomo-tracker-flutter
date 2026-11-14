from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Request
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
    db: Session = Depends(get_db),
):
    phone = repository.get_phone(db, phone_id)
    if phone is None:
        return HTMLResponse("Phone not found", status_code=404)

    messages = repository.list_messages(db, phone_id, start, end)
    total_in = sum(m.amount for m in messages if m.is_incoming)
    total_out = sum(m.amount for m in messages if not m.is_incoming)
    sender_groups = repository.group_by_sender(messages)

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
            "month_start": month_start.strftime("%Y-%m-%dT%H:%M"),
            "month_end": now.strftime("%Y-%m-%dT%H:%M"),
        },
    )


@router.post("/phones/{phone_id}/delete")
def delete_phone(phone_id: int, db: Session = Depends(get_db)):
    phone = repository.get_phone(db, phone_id)
    if phone is not None:
        repository.delete_phone(db, phone)
    return RedirectResponse(url="/", status_code=303)
