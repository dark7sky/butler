from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
import json
import logging

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None

from core.config import settings
from api.deps import get_current_user, get_db
from db.utils import list_account_tables

router = APIRouter()
logger = logging.getLogger(__name__)

class ChatRequest(BaseModel):
    query: str

_SUMMARY_TABLES = {"accounts_balance", "accounts_daydiff", "accounts_monthdiff", "accounts_diff"}

ASK_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_account_list",
            "description": (
                "accounts_info 테이블을 조회하여 모든 계좌 목록(계좌번호, 회사, 유형, 이름, 메모)을 반환한다. "
                "또한 toss, 지역화폐 등 특수 테이블 목록도 함께 반환한다."
            ),
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_account_history",
            "description": (
                "특정 계좌(account_number) 또는 특수 테이블(toss 등)의 잔액 이력을 조회한다. "
                "열: date, balance."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {"type": "string", "description": "조회할 테이블명 (계좌번호 또는 특수 테이블명)"},
                    "limit":      {"type": "integer", "description": "조회 건수 (기본 30)"},
                },
                "required": ["table_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_summary_table",
            "description": (
                "요약 테이블을 조회한다.\n"
                "- accounts_balance: 전체 잔액 합계 (date, balance)\n"
                "- accounts_daydiff: 일별 변동 (date, balance)\n"
                "- accounts_monthdiff: 월별 변동 (date, balance)\n"
                "- accounts_diff: 각 시점별 raw 변동 (date, balance)"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "enum": ["accounts_balance", "accounts_daydiff", "accounts_monthdiff", "accounts_diff"],
                        "description": "조회할 요약 테이블",
                    },
                    "limit": {"type": "integer", "description": "조회 건수 (기본 30)"},
                },
                "required": ["table_name"],
            },
        },
    },
]

def execute_ask_tool(db: Session, tool_name: str, args: dict) -> str:
    """GPT Function Calling 요청을 실행하여 결과를 문자열로 반환."""
    try:
        if tool_name == "get_account_list":
            accounts_res = db.execute(text("SELECT account_number, company, type, name, memo FROM accounts_info")).fetchall()
            accounts = [dict(r._mapping) for r in accounts_res]
            
            special = [t for t in list_account_tables(db) if not t.isnumeric()]
            return json.dumps({"accounts": accounts, "special_tables": special}, ensure_ascii=False, default=str)

        elif tool_name == "get_account_history":
            table_name = args.get("table_name", "")
            limit = min(int(args.get("limit", 30)), 200)
            
            if table_name not in set(list_account_tables(db)):
                return f"테이블 '{table_name}'이 존재하지 않습니다."
            
            rows = db.execute(text(f'SELECT date, balance FROM "{table_name}" ORDER BY date DESC LIMIT :l'), {"l": limit}).fetchall()
            return json.dumps([{"date": str(r[0]), "balance": float(r[1])} for r in rows], ensure_ascii=False)

        elif tool_name == "get_summary_table":
            table_name = args.get("table_name", "accounts_balance")
            if table_name not in _SUMMARY_TABLES:
                table_name = "accounts_balance"
            limit = min(int(args.get("limit", 30)), 200)
            
            rows = db.execute(text(f"SELECT date, balance FROM {table_name} ORDER BY date DESC LIMIT :l"), {"l": limit}).fetchall()
            return json.dumps([{"date": str(r[0]), "balance": float(r[1])} for r in rows], ensure_ascii=False)

        return "알 수 없는 도구입니다."
    except Exception as e:
        logger.error(f"Error in execute_ask_tool: {e}")
        return f"오류: {e}"

def call_llm_with_tools(client: OpenAI, db: Session, user_query: str, max_rounds: int = 6) -> str:
    system = (
        "당신은 한국어 재무 어시스턴트입니다. "
        "필요한 데이터는 도구를 이용해 DB에서 직접 조회하세요. "
        "답변은 한국어로 간결하고 데이터 기반으로 작성하세요. "
        "표가 필요하면 모노스페이스 텍스트 표로 정렬하세요. "
        "데이터가 부족하면 추정 대신 의거 데이터 부족을 명시하세요."
    )
    messages = [
        {"role": "system", "content": system},
        {"role": "user",   "content": user_query},
    ]
    for _ in range(max_rounds):
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.2,
            max_tokens=1000,
            messages=messages,
            tools=ASK_TOOLS,
            tool_choice="auto",
        )
        msg = resp.choices[0].message
        
        msg_dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            msg_dict["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                }
                for tc in msg.tool_calls
            ]
        messages.append(msg_dict)
        
        if not msg.tool_calls:
            return msg.content or ""
            
        for tc in msg.tool_calls:
            try:    args = json.loads(tc.function.arguments)
            except: args = {}
            result = execute_ask_tool(db, tc.function.name, args)
            messages.append({"role": "tool", "tool_call_id": tc.id, "content": result})
            
    return "응답을 생성하지 못했습니다. (최대 반복횟수 실패)"

@router.post("/ask")
async def chat_ask(
    request: ChatRequest,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if OpenAI is None or not settings.KEY_OPENAI:
        return {
            "status": "error",
            "answer": "OpenAI API가 설정되어 있지 않습니다."
        }
    
    try:
        client = OpenAI(api_key=settings.KEY_OPENAI)
        answer = call_llm_with_tools(client, db, request.query)
        return {"status": "success", "answer": answer}
    except Exception as e:
        logger.error(f"LLM Chat Error: {e}")
        return {"status": "error", "answer": f"LLM 오류: {e}"}
