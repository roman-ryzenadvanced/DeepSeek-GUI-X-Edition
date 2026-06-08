import { emptyUsageSnapshot } from '../../contracts/usage.js';
import { estimateDeepseekCacheSavings, estimateDeepseekCost } from './deepseek-pricing.js';
import { isToolResultBridgeItem, repairModelHistoryItems } from '../../domain/model-history-repair.js';
import { repairToolArguments } from './tool-argument-repair.js';
import { isDeepSeekHost, probeDeepSeekReachable } from './model-error-probe.js';
const DEFAULT_STREAM_IDLE_TIMEOUT_MS = 45_000;
/**
 * DeepSeek-compatible model client.
 *
 * This adapter focuses on the streaming chat completions shape used
 * by the GUI today. It supports tool calls, cache hit/miss counters
 * (when the provider reports them), and abort-signal cancellation.
 * The client is deliberately small so the rest of the runtime can be
 * built around the `ModelClient` port.
 */
export class DeepseekCompatModelClient {
    provider = 'deepseek-compat';
    model;
    config;
    fetchImpl;
    constructor(config) {
        this.config = config;
        this.model = config.model;
        this.fetchImpl = config.fetchImpl ?? fetch;
    }
    /**
     * Streams the model response for a turn. Each yielded chunk is one
     * of the kinds defined by `ModelStreamChunk`. The stream respects
     * the request's `abortSignal` between chunks.
     */
    async *stream(request) {
        if (request.abortSignal.aborted) {
            yield { kind: 'error', message: 'request was aborted before start' };
            return;
        }
        const url = this.buildUrl('/v1/chat/completions');
        const stream = request.stream ?? !this.config.nonStreaming;
        const body = this.buildRequestBody(request, stream);
        const headers = this.buildHeaders(stream);
        const init = {
            method: 'POST',
            headers,
            body: JSON.stringify(body),
            signal: request.abortSignal
        };
        let response;
        try {
            response = await this.fetchImpl(url, init);
        }
        catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            yield { kind: 'error', message: `model request failed: ${message}` };
            return;
        }
        if (!response.ok) {
            const text = await response.text();
            const classified = await this.classifyHttpError(response.status, text);
            yield {
                kind: 'error',
                message: classified.message,
                code: classified.code
            };
            return;
        }
        if (this.config.nonStreaming || response.headers.get('content-type')?.includes('application/json')) {
            const json = (await response.json());
            yield* this.materializeNonStreaming(json);
            return;
        }
        if (!response.body) {
            yield { kind: 'error', message: 'model response had no body' };
            return;
        }
        yield* this.streamSse(response.body, request.abortSignal);
    }
    buildUrl(path) {
        const base = this.config.baseUrl.replace(/\/+$/, '');
        return `${base}${path}`;
    }
    buildHeaders(stream) {
        const headers = {
            'Content-Type': 'application/json',
            Accept: stream ? 'text/event-stream' : 'application/json'
        };
        if (this.config.apiKey) {
            headers.Authorization = `Bearer ${this.config.apiKey}`;
        }
        return { ...headers, ...(this.config.headers ?? {}) };
    }
    async classifyHttpError(status, text) {
        const body = text.slice(0, 500);
        if (status === 429) {
            return {
                message: `model request was rate limited (HTTP 429): ${body}`,
                code: 'rate_limited'
            };
        }
        if (status >= 500 && isDeepSeekHost(this.config.baseUrl)) {
            const probe = await probeDeepSeekReachable({
                baseUrl: this.config.baseUrl,
                fetchImpl: this.fetchImpl
            });
            return {
                message: `model request failed with DeepSeek HTTP ${status}: ${body} ${probe.message}`,
                code: probe.reachable ? `deepseek_http_${status}` : 'deepseek_unreachable'
            };
        }
        return {
            message: `model request failed with status ${status}: ${body}`,
            code: `http_${status}`
        };
    }
    buildRequestBody(request, stream) {
        const requestModel = request.model?.trim();
        const model = requestModel || this.config.model;
        const messages = this.collectMessages(request, model);
        const body = {
            model,
            stream,
            messages
        };
        if (request.maxTokens !== undefined) {
            body.max_tokens = request.maxTokens;
        }
        if (request.temperature !== undefined) {
            body.temperature = request.temperature;
        }
        if (request.topP !== undefined) {
            body.top_p = request.topP;
        }
        if (request.responseFormat === 'json_object') {
            body.response_format = { type: 'json_object' };
        }
        const includeThinking = !isAzureOpenAiEndpoint(this.config.baseUrl);
        applyReasoningEffort(body, request.reasoningEffort, { includeThinking });
        if (includeThinking &&
            !Object.prototype.hasOwnProperty.call(body, 'thinking') &&
            isThinkingProducerModel(model)) {
            body.thinking = { type: 'enabled' };
        }
        const tools = normalizeToolSpecs(request.tools);
        if (tools.length > 0) {
            body.tools = tools.map((tool) => ({
                type: 'function',
                function: {
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.inputSchema
                }
            }));
        }
        return body;
    }
    collectMessages(request, model) {
        const out = [];
        if (request.systemPrompt) {
            out.push({ role: 'system', content: request.systemPrompt });
        }
        if (request.modeInstruction) {
            out.push({ role: 'system', content: request.modeInstruction });
        }
        for (const instruction of request.contextInstructions ?? []) {
            if (instruction.trim())
                out.push({ role: 'system', content: instruction });
        }
        const windowSize = this.config.historyLimit;
        const history = windowSize
            ? limitHistoryPreservingCompaction(request.history, windowSize)
            : request.history;
        const thinkingMode = requiresReasoningRoundTrip(request.reasoningEffort, model);
        out.push(...this.itemsToMessages(repairModelHistoryItems([...request.prefix, ...history]), thinkingMode));
        if (request.attachments?.length) {
            attachImagesToLatestUserMessage(out, request.attachments);
        }
        if (request.attachmentTextFallbacks?.length) {
            attachTextFallbacksToLatestUserMessage(out, request.attachmentTextFallbacks);
        }
        return normalizeThinkingAssistantMessages(healToolMessagePairs(out), thinkingMode);
    }
    itemsToMessages(items, thinkingMode) {
        const out = [];
        for (let index = 0; index < items.length; index += 1) {
            const item = items[index];
            if (isBridgeItemBeforeToolCall(items, index)) {
                continue;
            }
            if (thinkingMode && item?.kind === 'assistant_reasoning') {
                const next = items[index + 1];
                if (next?.kind === 'assistant_text' && next.turnId === item.turnId) {
                    out.push({
                        role: 'assistant',
                        content: next.text,
                        reasoning_content: reasoningContentOrSpace(item.text)
                    });
                    index += 1;
                }
                continue;
            }
            if (item?.kind === 'tool_call') {
                const block = this.toolCallBlockToMessages(items, index, thinkingMode);
                if (block) {
                    out.push(...block.messages);
                    index = block.nextIndex - 1;
                }
                continue;
            }
            if (item?.kind === 'tool_result')
                continue;
            const message = this.itemToMessage(item, thinkingMode);
            if (message)
                out.push(message);
        }
        return out;
    }
    toolCallBlockToMessages(items, startIndex, thinkingMode) {
        const calls = [];
        let index = startIndex;
        while (index < items.length && items[index]?.kind === 'tool_call') {
            calls.push(items[index]);
            index += 1;
        }
        if (calls.length === 0)
            return null;
        const turnId = calls[0]?.turnId ?? '';
        const expectedCallIds = new Set(calls.map((call) => call.callId));
        const seenResultIds = new Set();
        const resultMessages = [];
        const assistantText = [];
        const reasoningText = [];
        let bridgeIndex = startIndex - 1;
        while (bridgeIndex >= 0) {
            const item = items[bridgeIndex];
            if (!item || !isPreToolCallBridgeItem(item, turnId))
                break;
            if (item.kind === 'assistant_text' && item.text.trim()) {
                assistantText.unshift(item.text);
            }
            else if (item.kind === 'assistant_reasoning' && item.text.trim()) {
                reasoningText.unshift(item.text);
            }
            bridgeIndex -= 1;
        }
        let sawResult = false;
        while (index < items.length) {
            const item = items[index];
            if (!item)
                break;
            if (item.kind === 'tool_result') {
                sawResult = true;
                if (expectedCallIds.has(item.callId) && !seenResultIds.has(item.callId)) {
                    seenResultIds.add(item.callId);
                    resultMessages.push(this.toolResultToMessage(item));
                }
                index += 1;
                continue;
            }
            if (isToolResultBridgeItem(item, { turnId, sawResult })) {
                if (!sawResult) {
                    if (item.kind === 'assistant_text' && item.text.trim()) {
                        assistantText.push(item.text);
                    }
                    else if (item.kind === 'assistant_reasoning' && item.text.trim()) {
                        reasoningText.push(item.text);
                    }
                }
                index += 1;
                continue;
            }
            break;
        }
        if (![...expectedCallIds].every((callId) => seenResultIds.has(callId))) {
            return null;
        }
        return {
            messages: [
                {
                    role: 'assistant',
                    content: assistantText.length > 0 ? assistantText.join('\n') : '',
                    ...(thinkingMode ? { reasoning_content: reasoningContentOrSpace(reasoningText.join('\n')) } : {}),
                    tool_calls: calls.map((call) => this.toolCallToWire(call))
                },
                ...resultMessages
            ],
            nextIndex: index
        };
    }
    toolCallToWire(item) {
        return {
            id: item.callId,
            type: 'function',
            function: { name: item.toolName, arguments: JSON.stringify(item.arguments) }
        };
    }
    toolResultToMessage(item) {
        return {
            role: 'tool',
            content: toolResultContent(item.output),
            tool_call_id: item.callId
        };
    }
    itemToMessage(item, thinkingMode) {
        switch (item.kind) {
            case 'user_message':
                return { role: 'user', content: item.text };
            case 'assistant_text':
                return {
                    role: 'assistant',
                    content: item.text,
                    ...(thinkingMode ? { reasoning_content: ' ' } : {})
                };
            case 'assistant_reasoning':
                return null;
            case 'tool_call':
                return {
                    role: 'assistant',
                    content: '',
                    ...(thinkingMode ? { reasoning_content: ' ' } : {}),
                    tool_calls: [this.toolCallToWire(item)]
                };
            case 'tool_result':
                return this.toolResultToMessage(item);
            case 'compaction':
                return item.replacedTokens > 0
                    ? { role: 'system', content: `Conversation summary from earlier turns:\n${item.summary}` }
                    : null;
            case 'review':
                return item.status === 'completed' && item.reviewText?.trim()
                    ? { role: 'system', content: `Code review result from an earlier turn:\n${item.reviewText}` }
                    : null;
            case 'approval':
            case 'user_input':
            case 'error':
                return null;
        }
    }
    async *streamSse(body, signal) {
        const decoder = new TextDecoder('utf-8');
        const reader = body.getReader();
        let buffer = '';
        const pendingArguments = new Map();
        let usage = null;
        let textAccumulator = '';
        let reasoningAccumulator = '';
        let stopReason = 'stop';
        let finishReason = null;
        const idleTimeoutMs = normalizeStreamIdleTimeoutMs(this.config.streamIdleTimeoutMs);
        try {
            while (!signal.aborted) {
                const read = await readStreamChunk(reader, signal, idleTimeoutMs);
                if (read.kind === 'timeout') {
                    yield {
                        kind: 'error',
                        message: `model stream stalled for ${idleTimeoutMs}ms without data`,
                        code: 'stream_idle_timeout'
                    };
                    return;
                }
                if (read.kind === 'aborted')
                    break;
                if (read.kind === 'error') {
                    yield { kind: 'error', message: read.message, code: 'stream_read_error' };
                    return;
                }
                const { value, done } = read;
                if (done)
                    break;
                buffer += decoder.decode(value, { stream: true });
                let boundary;
                while ((boundary = buffer.indexOf('\n\n')) >= 0) {
                    const frame = buffer.slice(0, boundary);
                    buffer = buffer.slice(boundary + 2);
                    const dataLines = frame
                        .split('\n')
                        .filter((line) => line.startsWith('data:'))
                        .map((line) => line.slice(5).trim())
                        .join('');
                    if (!dataLines)
                        continue;
                    if (dataLines === '[DONE]') {
                        finishReason = finishReason ?? 'stop';
                        break;
                    }
                    let payload;
                    try {
                        payload = JSON.parse(dataLines);
                    }
                    catch {
                        continue;
                    }
                    const result = this.consumeStreamPayload(payload, pendingArguments, textAccumulator, reasoningAccumulator);
                    textAccumulator = result.text;
                    reasoningAccumulator = result.reasoning;
                    if (result.usage)
                        usage = result.usage;
                    if (result.finishReason)
                        finishReason = result.finishReason;
                    for (const chunk of result.chunks)
                        yield chunk;
                }
                if (finishReason === 'stop' || finishReason === 'tool_calls' || finishReason === 'length')
                    break;
            }
        }
        finally {
            try {
                reader.releaseLock();
            }
            catch {
                // The stream may already be released; ignore.
            }
        }
        if (signal.aborted) {
            yield { kind: 'error', message: 'request was aborted' };
            return;
        }
        if (usage)
            yield { kind: 'usage', usage };
        stopReason = (() => {
            switch (finishReason) {
                case 'tool_calls':
                    return 'tool_calls';
                case 'length':
                    return 'length';
                case 'error':
                    return 'error';
                default:
                    return 'stop';
            }
        })();
        yield { kind: 'completed', stopReason };
    }
    consumeStreamPayload(payload, pendingArguments, textAccumulator, reasoningAccumulator) {
        const chunks = [];
        let text = textAccumulator;
        let reasoning = reasoningAccumulator;
        let finishReason = null;
        let usage = null;
        const choice = payload.choices?.[0];
        if (choice && typeof choice === 'object') {
            const delta = choice.delta;
            if (delta && typeof delta === 'object') {
                const content = delta.content;
                if (typeof content === 'string' && content.length > 0) {
                    text += content;
                    chunks.push({ kind: 'assistant_text_delta', text: content });
                }
                const reasoningContent = delta.reasoning_content ?? delta.reasoning;
                if (typeof reasoningContent === 'string' && reasoningContent.length > 0) {
                    reasoning += reasoningContent;
                    chunks.push({ kind: 'assistant_reasoning_delta', text: reasoningContent });
                }
                const toolCalls = delta.tool_calls;
                if (Array.isArray(toolCalls)) {
                    for (const call of toolCalls) {
                        const id = resolveToolCallDeltaId(call, pendingArguments);
                        const existing = pendingArguments.get(id) ?? { index: numericIndex(call.index), name: undefined, arguments: '' };
                        const resolvedIndex = numericIndex(call.index);
                        if (resolvedIndex !== undefined)
                            existing.index = resolvedIndex;
                        if (call.function?.name)
                            existing.name = call.function.name;
                        if (typeof call.function?.arguments === 'string') {
                            existing.arguments += call.function.arguments;
                            chunks.push({
                                kind: 'tool_call_delta',
                                callId: id,
                                toolName: existing.name,
                                argumentsDelta: call.function.arguments
                            });
                        }
                        pendingArguments.set(id, existing);
                    }
                }
            }
            if (typeof choice.finish_reason === 'string') {
                finishReason = choice.finish_reason;
            }
        }
        const usagePayload = payload.usage;
        if (usagePayload) {
            usage = this.mapUsage(usagePayload);
        }
        if (finishReason === 'tool_calls' && pendingArguments.size > 0) {
            for (const [callId, value] of pendingArguments) {
                if (!value.name)
                    continue;
                const args = this.parseToolArguments(value.arguments);
                chunks.push({
                    kind: 'tool_call_complete',
                    callId,
                    toolName: value.name,
                    arguments: args
                });
            }
            pendingArguments.clear();
        }
        return { chunks, text, reasoning, finishReason, usage };
    }
    *materializeNonStreaming(payload) {
        const choice = payload.choices?.[0];
        if (!choice) {
            yield { kind: 'error', message: 'model response contained no choices' };
            return;
        }
        const text = typeof choice.message?.content === 'string' ? choice.message.content : '';
        const reasoning = reasoningFromMessage(choice.message);
        if (reasoning) {
            yield { kind: 'assistant_reasoning_delta', text: reasoning };
        }
        if (text) {
            yield { kind: 'assistant_text_delta', text };
        }
        if (Array.isArray(choice.message?.tool_calls)) {
            for (const call of choice.message.tool_calls) {
                const args = this.parseToolArguments(call.function?.arguments ?? '{}');
                yield {
                    kind: 'tool_call_complete',
                    callId: call.id,
                    toolName: call.function.name,
                    arguments: args
                };
            }
        }
        if (payload.usage) {
            yield { kind: 'usage', usage: this.mapUsage(payload.usage) };
        }
        let stopReason = 'stop';
        if (choice.finish_reason === 'tool_calls')
            stopReason = 'tool_calls';
        else if (choice.finish_reason === 'length')
            stopReason = 'length';
        else if (choice.finish_reason === 'error')
            stopReason = 'error';
        yield { kind: 'completed', stopReason };
    }
    mapUsage(usage) {
        const promptTokens = Number(usage.prompt_tokens ?? usage.prompt_eval_count ?? 0) || 0;
        const completionTokens = Number(usage.completion_tokens ?? usage.eval_count ?? 0) || 0;
        const totalTokens = Number(usage.total_tokens ?? promptTokens + completionTokens) || 0;
        const promptDetails = usage.prompt_tokens_details;
        const nativeHit = Number(usage.prompt_cache_hit_tokens ?? 0) || 0;
        const nativeMiss = Number(usage.prompt_cache_miss_tokens ?? 0) || 0;
        const hasNativeCache = nativeHit > 0 || nativeMiss > 0;
        const cachedTokens = Number(promptDetails?.cached_tokens ?? 0) || 0;
        const cacheRead = Number(usage.cache_read_input_tokens ?? 0) || 0;
        const cacheCreation = Number(usage.cache_creation_input_tokens ?? 0) || 0;
        const cacheHit = hasNativeCache ? nativeHit : (cachedTokens > 0 ? cachedTokens : cacheRead);
        const cacheMiss = hasNativeCache ? nativeMiss : Math.max(promptTokens - cacheHit, 0);
        const cacheTotal = cacheHit + cacheMiss;
        const cacheHitRate = cacheTotal === 0 ? null : cacheHit / cacheTotal;
        const estimatedCost = estimateDeepseekCost({
            model: this.config.model,
            cacheHitTokens: cacheHit,
            cacheMissTokens: cacheMiss,
            outputTokens: completionTokens
        });
        const estimatedSavings = estimateDeepseekCacheSavings({
            model: this.config.model,
            cacheHitTokens: cacheHit
        });
        const reportedCostUsd = Number(usage.cost_usd ?? usage.costUsd);
        const reportedCostCny = Number(usage.cost_cny ?? usage.costCny);
        return {
            ...emptyUsageSnapshot(),
            promptTokens,
            completionTokens,
            totalTokens,
            cachedTokens: cacheHit || cachedTokens || cacheRead || 0,
            cacheHitTokens: cacheHit,
            cacheMissTokens: cacheMiss,
            cacheHitRate,
            turns: 1,
            costUsd: Number.isFinite(reportedCostUsd) ? reportedCostUsd : estimatedCost?.costUsd,
            costCny: Number.isFinite(reportedCostCny) ? reportedCostCny : estimatedCost?.costCny,
            cacheSavingsUsd: estimatedSavings?.costUsd,
            cacheSavingsCny: estimatedSavings?.costCny
        };
    }
    parseToolArguments(raw) {
        return repairToolArguments(raw).arguments;
    }
}
function normalizeToolSpecs(tools) {
    return [...tools]
        .map((tool) => ({
        name: tool.name,
        description: tool.description,
        inputSchema: canonicalizeSchema(tool.inputSchema)
    }))
        .sort((a, b) => a.name.localeCompare(b.name));
}
function applyReasoningEffort(body, effort, options = {}) {
    const normalized = effort?.trim().toLowerCase();
    if (!normalized)
        return;
    const includeThinking = options.includeThinking !== false;
    switch (normalized) {
        case 'off':
        case 'disabled':
        case 'none':
        case 'false':
            if (includeThinking)
                body.thinking = { type: 'disabled' };
            break;
        case 'low':
        case 'minimal':
        case 'medium':
        case 'mid':
        case 'high':
            body.reasoning_effort = 'high';
            if (includeThinking)
                body.thinking = { type: 'enabled' };
            break;
        case 'max':
        case 'maximum':
        case 'xhigh':
            body.reasoning_effort = 'max';
            if (includeThinking)
                body.thinking = { type: 'enabled' };
            break;
    }
}
function isAzureOpenAiEndpoint(baseUrl) {
    try {
        const url = new URL(baseUrl);
        const host = url.hostname.toLowerCase();
        return host.endsWith('.openai.azure.com') || host.endsWith('.cognitiveservices.azure.com');
    }
    catch {
        return /\.openai\.azure\.com\b|\.cognitiveservices\.azure\.com\b/i.test(baseUrl);
    }
}
function isThinkingMode(effort) {
    const normalized = effort?.trim().toLowerCase();
    if (!normalized)
        return false;
    return !['off', 'disabled', 'none', 'false'].includes(normalized);
}
function requiresReasoningRoundTrip(effort, model) {
    return isThinkingMode(effort) || isThinkingProducerModel(model);
}
function isThinkingProducerModel(model) {
    const normalized = normalizeModelId(model);
    if (!normalized)
        return false;
    return normalized === 'deepseek-v4-pro' ||
        normalized === 'deepseek-v4-flash' ||
        normalized.includes('deepseek-reasoner') ||
        normalized.endsWith('/deepseek-v4-pro') ||
        normalized.endsWith('/deepseek-v4-flash');
}
function reasoningContentOrSpace(text) {
    return text.trim() ? text : ' ';
}
function toolResultContent(output) {
    if (typeof output === 'string')
        return output;
    return JSON.stringify(output) ?? '';
}
function reasoningFromMessage(message) {
    if (!message)
        return '';
    const value = message.reasoning_content ??
        message.reasoning;
    return typeof value === 'string' ? value : '';
}
function isPreToolCallBridgeItem(item, turnId) {
    if (item.turnId !== turnId)
        return false;
    return item.kind === 'assistant_reasoning' || item.kind === 'assistant_text';
}
function isBridgeItemBeforeToolCall(items, index) {
    const item = items[index];
    if (!item || (item.kind !== 'assistant_reasoning' && item.kind !== 'assistant_text')) {
        return false;
    }
    let cursor = index + 1;
    while (cursor < items.length) {
        const next = items[cursor];
        if (!next)
            return false;
        if (next.kind === 'assistant_reasoning' || next.kind === 'assistant_text') {
            if (next.turnId !== item.turnId)
                return false;
            cursor += 1;
            continue;
        }
        return next.kind === 'tool_call' && next.turnId === item.turnId;
    }
    return false;
}
function normalizeThinkingAssistantMessages(messages, thinkingMode) {
    if (!thinkingMode)
        return messages;
    return messages.map((message) => {
        if (message.role !== 'assistant')
            return message;
        const next = { ...message };
        if (next.content == null)
            next.content = '';
        if (!Object.prototype.hasOwnProperty.call(next, 'reasoning_content') ||
            next.reasoning_content == null ||
            !next.reasoning_content.trim()) {
            next.reasoning_content = ' ';
        }
        return next;
    });
}
function canonicalizeSchema(value) {
    const canonical = canonicalize(value);
    return canonical && typeof canonical === 'object' && !Array.isArray(canonical)
        ? canonical
        : {};
}
function normalizeModelId(model) {
    return model?.trim().toLowerCase() ?? '';
}
function normalizeStreamIdleTimeoutMs(value) {
    if (value === undefined)
        return DEFAULT_STREAM_IDLE_TIMEOUT_MS;
    if (!Number.isFinite(value))
        return DEFAULT_STREAM_IDLE_TIMEOUT_MS;
    return Math.max(0, Math.floor(value));
}
async function readStreamChunk(reader, signal, idleTimeoutMs) {
    if (signal.aborted)
        return { kind: 'aborted' };
    let timeout;
    let cleanupAbort;
    const readPromise = reader.read()
        .then((result) => ({ kind: 'chunk', ...result }))
        .catch((error) => {
        if (signal.aborted)
            return { kind: 'aborted' };
        const message = error instanceof Error ? error.message : String(error);
        return { kind: 'error', message: `model stream read failed: ${message}` };
    });
    const abortPromise = new Promise((resolve) => {
        const onAbort = () => resolve({ kind: 'aborted' });
        if (signal.aborted) {
            resolve({ kind: 'aborted' });
            return;
        }
        signal.addEventListener('abort', onAbort, { once: true });
        cleanupAbort = () => signal.removeEventListener('abort', onAbort);
    });
    const candidates = [readPromise, abortPromise];
    if (idleTimeoutMs > 0) {
        candidates.push(new Promise((resolve) => {
            timeout = setTimeout(() => resolve({ kind: 'timeout' }), idleTimeoutMs);
        }));
    }
    const result = await Promise.race(candidates);
    if (timeout)
        clearTimeout(timeout);
    cleanupAbort?.();
    if (result.kind === 'timeout') {
        try {
            await reader.cancel('model stream idle timeout');
        }
        catch {
            // Best-effort cancellation; the caller will surface the timeout.
        }
    }
    return result;
}
function canonicalize(value) {
    if (Array.isArray(value))
        return value.map(canonicalize);
    if (!value || typeof value !== 'object')
        return value;
    const out = {};
    for (const key of Object.keys(value).sort()) {
        out[key] = canonicalize(value[key]);
    }
    return out;
}
function resolveToolCallDeltaId(call, pending) {
    const index = numericIndex(call.index);
    const existingByIndex = findPendingToolCallIdByIndex(pending, index);
    if (call.id) {
        if (existingByIndex && existingByIndex !== call.id) {
            const existing = pending.get(existingByIndex);
            if (existing) {
                pending.delete(existingByIndex);
                pending.set(call.id, existing);
            }
        }
        return call.id;
    }
    return existingByIndex ?? `call_${pending.size + 1}`;
}
function findPendingToolCallIdByIndex(pending, index) {
    if (index === undefined)
        return undefined;
    for (const [callId, value] of pending) {
        if (value.index === index)
            return callId;
    }
    return undefined;
}
function numericIndex(index) {
    return typeof index === 'number' && Number.isInteger(index) && index >= 0
        ? index
        : undefined;
}
function healToolMessagePairs(messages) {
    const healed = [];
    for (let i = 0; i < messages.length; i += 1) {
        const message = messages[i];
        if (message.role === 'tool') {
            continue;
        }
        if (message.role === 'assistant' && message.tool_calls?.length) {
            const expectedIds = new Set(message.tool_calls.map((call) => call.id));
            const toolResults = [];
            let j = i + 1;
            while (j < messages.length && messages[j].role === 'tool') {
                const toolResult = messages[j];
                if (toolResult.tool_call_id && expectedIds.has(toolResult.tool_call_id)) {
                    toolResults.push(toolResult);
                }
                j += 1;
            }
            const seenIds = new Set(toolResults.map((toolResult) => toolResult.tool_call_id));
            if ([...expectedIds].every((id) => seenIds.has(id))) {
                healed.push(message, ...toolResults);
            }
            i = j - 1;
            continue;
        }
        healed.push(message);
    }
    return healed;
}
function attachImagesToLatestUserMessage(messages, attachments) {
    for (let index = messages.length - 1; index >= 0; index -= 1) {
        const message = messages[index];
        if (message.role !== 'user')
            continue;
        const parts = [];
        if (typeof message.content === 'string' && message.content) {
            parts.push({ type: 'text', text: message.content });
        }
        for (const attachment of attachments) {
            parts.push({
                type: 'image_url',
                image_url: {
                    url: `data:${attachment.mimeType};base64,${attachment.dataBase64}`
                }
            });
        }
        message.content = parts;
        return;
    }
}
function attachTextFallbacksToLatestUserMessage(messages, attachments) {
    const text = attachments.map(formatAttachmentTextFallback).join('\n\n');
    for (let index = messages.length - 1; index >= 0; index -= 1) {
        const message = messages[index];
        if (message.role !== 'user')
            continue;
        if (typeof message.content === 'string') {
            message.content = message.content ? `${message.content}\n\n${text}` : text;
            return;
        }
        if (Array.isArray(message.content)) {
            message.content.push({ type: 'text', text });
            return;
        }
        message.content = text;
        return;
    }
}
function formatAttachmentTextFallback(attachment) {
    return [
        '[Attached image as base64 text]',
        `Name: ${attachment.name}`,
        `MIME: ${attachment.mimeType}`,
        `Dimensions: ${formatAttachmentDimensions(attachment)}`,
        `Bytes: ${attachment.byteSize}`,
        'Base64:',
        '```base64',
        attachment.dataBase64,
        '```',
        '[/Attached image]'
    ].join('\n');
}
function formatAttachmentDimensions(attachment) {
    return attachment.width && attachment.height ? `${attachment.width}x${attachment.height}` : 'unknown';
}
function limitHistoryPreservingCompaction(history, windowSize) {
    if (history.length <= windowSize)
        return history;
    const windowStart = history.length - windowSize;
    const limited = history.slice(windowStart);
    if (limited.some((item) => item.kind === 'compaction' && item.replacedTokens > 0)) {
        return limited;
    }
    for (let index = windowStart - 1; index >= 0; index -= 1) {
        const item = history[index];
        if (item.kind !== 'compaction' || item.replacedTokens === 0)
            continue;
        return windowSize <= 1 ? [item] : [item, ...history.slice(-(windowSize - 1))];
    }
    return limited;
}
//# sourceMappingURL=deepseek-compat-model-client.js.map