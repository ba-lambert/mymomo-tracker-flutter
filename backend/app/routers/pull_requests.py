from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import repository, schemas
from ..database import get_db

router = APIRouter(prefix="/api", tags=["pull-requests"])


@router.get(
    "/phones/by-name/{phone_name}/pending-pull",
    response_model=Optional[schemas.PendingPull],
)
def get_pending_pull(phone_name: str, db: Session = Depends(get_db)):
    """Polled by the phone's background task to ask "is there a dashboard-requested export waiting for me?"."""
    phone = repository.get_phone_by_name(db, phone_name.strip())
    if phone is None:
        raise HTTPException(status_code=404, detail="Phone not found")

    pull_request = repository.get_oldest_pending_pull_request(db, phone.id)
    if pull_request is None:
        return None

    return schemas.PendingPull(
        id=pull_request.id,
        start_date=pull_request.start_date,
        end_date=pull_request.end_date,
    )


@router.post("/pull-requests/{pull_request_id}/complete", response_model=schemas.PullRequestOut)
def complete_pull(
    pull_request_id: int,
    payload: schemas.PullRequestComplete,
    db: Session = Depends(get_db),
):
    """Called by the phone once it has exported and uploaded the requested range."""
    pull_request = repository.get_pull_request(db, pull_request_id)
    if pull_request is None:
        raise HTTPException(status_code=404, detail="Pull request not found")

    return repository.complete_pull_request(
        db, pull_request, payload.status, payload.message_count
    )
