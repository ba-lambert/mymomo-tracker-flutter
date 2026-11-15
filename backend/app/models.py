from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from .database import Base


class Phone(Base):
    """A device running the mobile app, identified by the name its owner chose."""

    __tablename__ = "phones"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    registered_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_seen_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    messages = relationship(
        "Message", back_populates="phone", cascade="all, delete-orphan"
    )
    pull_requests = relationship(
        "PullRequest", back_populates="phone", cascade="all, delete-orphan"
    )


class Message(Base):
    """One exported message belonging to a phone, from SMS or WhatsApp."""

    __tablename__ = "messages"
    __table_args__ = (
        UniqueConstraint(
            "phone_id", "sender", "date", "body", name="uq_phone_sender_date_body"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    phone_id = Column(Integer, ForeignKey("phones.id"), nullable=False, index=True)

    sender = Column(String, nullable=False, default="unknown", index=True)
    contact_name = Column(String, nullable=True, index=True)
    body = Column(String, nullable=False)
    date = Column(DateTime, nullable=False, index=True)
    amount = Column(Float, default=0)
    description = Column(String, default="")
    reference = Column(String, nullable=True)
    is_incoming = Column(Boolean, default=False)
    transaction_type = Column(String, nullable=False, default="other", index=True)
    source = Column(String, nullable=False, default="sms", index=True)

    uploaded_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    phone = relationship("Phone", back_populates="messages")


class PullRequest(Base):
    """A dashboard-initiated request for a phone to export and upload SMS
    for a given date range the next time it checks in.

    The phone has no way to be pushed to directly, so it polls for this
    instead: the background task (or a manual sync) asks whether one is
    pending, services it, then marks it complete.
    """

    __tablename__ = "pull_requests"

    id = Column(Integer, primary_key=True, index=True)
    phone_id = Column(Integer, ForeignKey("phones.id"), nullable=False, index=True)

    start_date = Column(DateTime, nullable=True)
    end_date = Column(DateTime, nullable=True)
    status = Column(String, nullable=False, default="pending", index=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    completed_at = Column(DateTime, nullable=True)
    message_count = Column(Integer, nullable=True)

    phone = relationship("Phone", back_populates="pull_requests")
