from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import repository, schemas
from ..database import get_db

router = APIRouter(prefix="/api/phones", tags=["phones"])


@router.post("/register", response_model=schemas.PhoneOut)
def register_phone(payload: schemas.PhoneRegister, db: Session = Depends(get_db)):
    """Registers a phone by name, or refreshes it if that name already exists."""
    return repository.register_phone(db, payload.name.strip())


@router.get("", response_model=list[schemas.PhoneWithCount])
def list_phones(db: Session = Depends(get_db)):
    return repository.list_phones_with_counts(db)


@router.delete("/{phone_id}", status_code=204)
def delete_phone(phone_id: int, db: Session = Depends(get_db)):
    phone = repository.get_phone(db, phone_id)
    if phone is None:
        raise HTTPException(status_code=404, detail="Phone not found")
    repository.delete_phone(db, phone)
