import json
import logging

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None

from api.deps import get_current_user, get_db
from core.config import settings
from db.utils import account_exists, fetch_summary_rows, list_accounts, serialize_timestamp

router = APIRouter()
logger = logging.getLogger(__name__)


class ChatRequest(BaseModel):
    query: str


_SUMMARY_TABLES = (
    "accounts_balance",
    "accounts_daydiff",
    "accounts_monthdiff",
    "accounts_diff",
)

ASK_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_account_list",
            "description": (
                "Return all accounts from the normalized accounts table. "
                "Include metadata and the list of special account keys."
            ),
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_account_history",
            "description": (
                "Return recent history for one account key. "
                "The result contains date and balance fields."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "Account key to inspect.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum row count, default 30.",
                    },
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
                "Return normalized portfolio summary rows. "
                "Supported names are accounts_balance, accounts_daydiff, "
                "accounts_monthdiff, and accounts_diff."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "enum": list(_SUMMARY_TABLES),
                        "description": "Summary table alias.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum row count, default 30.",
                    },
                },
                "required": ["table_name"],
            },
        },
    },
]


def execute_ask_tool(db: Session, tool_name: str, args: dict) -> str:
    try:
        if tool_name == "get_account_list":
            accounts = []
            special_tables = []
            for row in list_accounts(db):
                item = {
                    "account_number": row["account_key"],
                    "company": row["company"],
                    "type": row["type"],
                    "name": row["name"],
                    "memo": row["memo"],
                    "is_special": bool(row["is_special"]),
                    "is_active": bool(row["is_active"]),
                }
                accounts.append(item)
                if row["is_special"]:
                    special_tables.append(row["account_key"])
            return json.dumps(
                {"accounts": accounts, "special_tables": special_tables},
                ensure_ascii=False,
                default=str,
            )

        if tool_name == "get_account_history":
            account_key = str(args.get("table_name", "")).strip()
            limit = max(1, min(int(args.get("limit", 30)), 200))
            if not account_exists(db, account_key):
                return f"Account '{account_key}' not found."

            rows = db.execute(
                text(
                    """
                    SELECT recorded_at, balance
                    FROM account_balance_history
                    WHERE account_key = :account_key
                    ORDER BY recorded_at DESC
                    LIMIT :limit
                    """
                ),
                {"account_key": account_key, "limit": limit},
            ).fetchall()
            payload = [
                {"date": serialize_timestamp(row[0]), "balance": float(row[1])}
                for row in rows
            ]
            return json.dumps(payload, ensure_ascii=False)

        if tool_name == "get_summary_table":
            table_name = str(args.get("table_name", "accounts_balance"))
            limit = max(1, min(int(args.get("limit", 30)), 200))
            if table_name not in _SUMMARY_TABLES:
                table_name = "accounts_balance"
            return json.dumps(fetch_summary_rows(db, table_name, limit), ensure_ascii=False)

        return "Unsupported tool."
    except Exception as exc:
        logger.error("Error in execute_ask_tool: %s", exc)
        return f"Error: {exc}"


def call_llm_with_tools(client: OpenAI, db: Session, user_query: str, max_rounds: int = 6) -> str:
    system = (
        "You are a finance assistant for a personal account tracker. "
        "Use the tools to inspect the database directly. "
        "Answer concisely and do not invent missing data."
    )
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": user_query},
    ]
    for _ in range(max_rounds):
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.2,
            max_tokens=1000,
            messages=messages,
            tools=ASK_TOOLS,
            tool_choice="auto",
        )
        message = response.choices[0].message

        assistant_message = {"role": "assistant", "content": message.content or ""}
        if message.tool_calls:
            assistant_message["tool_calls"] = [
                {
                    "id": tool_call.id,
                    "type": "function",
                    "function": {
                        "name": tool_call.function.name,
                        "arguments": tool_call.function.arguments,
                    },
                }
                for tool_call in message.tool_calls
            ]
        messages.append(assistant_message)

        if not message.tool_calls:
            return message.content or ""

        for tool_call in message.tool_calls:
            try:
                arguments = json.loads(tool_call.function.arguments)
            except Exception:
                arguments = {}
            result = execute_ask_tool(db, tool_call.function.name, arguments)
            messages.append(
                {"role": "tool", "tool_call_id": tool_call.id, "content": result}
            )

    return "Could not produce an answer within the allowed tool rounds."


@router.post("/ask")
async def chat_ask(
    request: ChatRequest,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if OpenAI is None or not settings.KEY_OPENAI:
        return {"status": "error", "answer": "OpenAI API is not configured."}

    try:
        client = OpenAI(api_key=settings.KEY_OPENAI)
        answer = call_llm_with_tools(client, db, request.query)
        return {"status": "success", "answer": answer}
    except Exception as exc:
        logger.error("LLM Chat Error: %s", exc)
        return {"status": "error", "answer": f"LLM error: {exc}"}
