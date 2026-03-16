from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from api.deps import get_current_user, get_db
from schemas.input import ManualInputCreate, ManualInputResponse
from db.models import ManualInput

router = APIRouter()

@router.get("/", response_model=List[ManualInputResponse])
async def read_manual_inputs(
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    inputs = db.query(ManualInput).all()
    return inputs

@router.post("/", response_model=ManualInputResponse)
async def create_manual_input(
    item: ManualInputCreate,
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    # Add or Edit (Upsert)
    db_item = db.query(ManualInput).filter(ManualInput.key_name == item.key_name).first()
    if db_item:
        db_item.value = item.value
    else:
        db_item = ManualInput(key_name=item.key_name, value=item.value)
        db.add(db_item)
    
    db.commit()
    db.refresh(db_item)
    return db_item

@router.delete("/{item_id}")
async def delete_manual_input(
    item_id: int,
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    db_item = db.query(ManualInput).filter(ManualInput.id == item_id).first()
    if not db_item:
        raise HTTPException(status_code=404, detail="Item not found")
    
    db.delete(db_item)
    db.commit()
    return {"status": "success", "message": f"Item {item_id} deleted"}
