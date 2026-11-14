from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import models, schemas
from .sms_parser import parse_message


def get_phone_by_name(db: Session, name: str) -> Optional[models.Phone]:
    return db.query(models.Phone).filter(models.Phone.name == name).first()


def get_phone(db: Session, phone_id: int) -> Optional[models.Phone]:
    return db.query(models.Phone).filter(models.Phone.id == phone_id).first()


def register_phone(db: Session, name: str) -> models.Phone:
    """Creates the phone if new, or just refreshes its last-seen timestamp."""
    phone = get_phone_by_name(db, name)
    if phone is None:
        phone = models.Phone(name=name)
        db.add(phone)
    else:
        phone.last_seen_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(phone)
    return phone


def list_phones_with_counts(db: Session) -> List[schemas.PhoneWithCount]:
    rows = (
        db.query(models.Phone, func.count(models.Message.id))
        .outerjoin(models.Message)
        .group_by(models.Phone.id)
        .order_by(models.Phone.name)
        .all()
    )
    return [
        schemas.PhoneWithCount(
            id=phone.id,
            name=phone.name,
            registered_at=phone.registered_at,
            last_seen_at=phone.last_seen_at,
            message_count=count,
        )
        for phone, count in rows
    ]


def delete_phone(db: Session, phone: models.Phone) -> None:
    db.delete(phone)
    db.commit()


def insert_messages(
    db: Session, phone: models.Phone, messages: List[schemas.MessageIn]
) -> tuple[int, int]:
    """Inserts messages for a phone, skipping ones already stored.

    Duplicates are detected by (phone, sender, date, body), since the same
    SMS re-exported twice should not be double-counted.
    @returns tuple of (inserted, skipped_duplicates)
    """
    inserted = 0
    skipped = 0
    for message in messages:
        parsed = parse_message(message.body)
        record = models.Message(
            phone_id=phone.id,
            sender=message.sender,
            contact_name=message.contact_name,
            body=message.body,
            date=message.date,
            amount=parsed.amount,
            description=parsed.description,
            reference=parsed.reference,
            is_incoming=parsed.is_incoming,
            transaction_type=parsed.transaction_type,
        )
        db.add(record)
        try:
            db.commit()
            inserted += 1
        except IntegrityError:
            db.rollback()
            skipped += 1

    phone.last_seen_at = datetime.now(timezone.utc)
    db.commit()
    return inserted, skipped


def list_messages(
    db: Session,
    phone_id: int,
    start: Optional[datetime] = None,
    end: Optional[datetime] = None,
) -> List[models.Message]:
    query = db.query(models.Message).filter(models.Message.phone_id == phone_id)
    if start is not None:
        query = query.filter(models.Message.date >= start)
    if end is not None:
        query = query.filter(models.Message.date <= end)
    return query.order_by(models.Message.sender, models.Message.date.desc()).all()


def group_by_sender(
    messages: List[models.Message],
) -> List[tuple[str, List[models.Message]]]:
    """Groups already-sorted messages by their SMS sender, preserving order.

    Grouping is by the raw sender address/shortcode (M-Money, EQUITYBANK,
    a contact's number, ...), not by the transaction counterparty, so all
    MoMo activity stays under one "M-Money" group instead of being
    scattered across every person paid or paid by.
    """
    groups: dict[str, List[models.Message]] = {}
    for message in messages:
        groups.setdefault(message.sender, []).append(message)
    return list(groups.items())
