# MoMo Tracker Backend

FastAPI backend for the MoMo Tracker class project. Receives exported MoMo SMS
from the Flutter app, grouped per phone, and serves a small HTML dashboard plus
a JSON API for the React frontend.

## Run

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Dashboard: http://localhost:8000/
API docs: http://localhost:8000/docs

## API

- `POST /api/phones/register` `{ "name": "Lambert's Pixel" }` — registers (or
  refreshes) a phone by name.
- `GET /api/phones` — list phones with message counts.
- `DELETE /api/phones/{id}` — remove a phone and its messages.
- `POST /api/messages/upload`
  ```json
  {
    "phone_name": "Lambert's Pixel",
    "messages": [
      {
        "body": "You have received 2,000 RWF ... Id: 123456.",
        "date": "2026-11-01T10:00:00",
        "amount": 2000,
        "description": "You have received 2,000 RWF",
        "reference": "123456",
        "is_incoming": true
      }
    ]
  }
  ```
  Creates the phone if it doesn't exist yet. Duplicate `(phone, reference, date)`
  entries are skipped.
- `GET /api/phones/{id}/messages?start=...&end=...` — messages for a phone,
  optionally filtered by ISO date range.

## Dashboard

`/` lists every phone that has exported data, with message counts and a delete
action. `/phones/{id}` shows that phone's messages with income/expense totals
and a date-range filter.

## Data model

SQLite by default (`momo_tracker.db`, created on first run). Override with the
`DATABASE_URL` env var to point at Postgres/MySQL instead.
