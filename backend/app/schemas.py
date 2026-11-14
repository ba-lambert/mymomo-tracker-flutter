from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class PhoneRegister(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class PhoneOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    registered_at: datetime
    last_seen_at: datetime


class PhoneWithCount(PhoneOut):
    message_count: int


class MessageIn(BaseModel):
    sender: str = "unknown"
    contact_name: Optional[str] = None
    body: str
    date: datetime
    amount: float = 0
    description: str = ""
    reference: Optional[str] = None
    is_incoming: bool = False
    transaction_type: str = "other"


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    sender: str
    contact_name: Optional[str]
    body: str
    date: datetime
    amount: float
    description: str
    reference: Optional[str]
    is_incoming: bool
    transaction_type: str
    uploaded_at: datetime


class UploadRequest(BaseModel):
    phone_name: str = Field(min_length=1, max_length=100)
    messages: List[MessageIn]


class UploadResult(BaseModel):
    phone_name: str
    received: int
    inserted: int
    skipped_duplicates: int
