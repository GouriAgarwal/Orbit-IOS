import { HttpException, Injectable, ServiceUnavailableException } from '@nestjs/common';

type GeminiResponse = {
  candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
};

@Injectable()
export class GeminiService {
  private readonly usage = new Map<string, { day: string; count: number }>();

  async generateJSON<T>(userId: string, prompt: string): Promise<T> {
    const apiKey = process.env.GEMINI_API_KEY;
    const model = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
    const trialUntil = Date.parse(process.env.GEMINI_TRIAL_UNTIL ?? '');
    if (!apiKey || !Number.isFinite(trialUntil) || Date.now() > trialUntil) {
      throw new ServiceUnavailableException({ error: { code: 'AI_TRIAL_UNAVAILABLE', message: 'Orbit AI is not available right now. You can still create this manually.' } });
    }

    this.consumeTrialRequest(userId);
    let response: Response;
    try {
      response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { responseMimeType: 'application/json', temperature: 0.35, maxOutputTokens: 1100 },
        }),
        signal: AbortSignal.timeout(20_000),
      });
    } catch {
      throw new ServiceUnavailableException({ error: { code: 'AI_TEMPORARILY_UNAVAILABLE', message: 'Orbit AI could not connect. Please try again or continue manually.' } });
    }
    if (!response.ok) {
      // Keep provider response bodies and credentials out of application logs and client errors.
      throw new ServiceUnavailableException({ error: { code: 'AI_TEMPORARILY_UNAVAILABLE', message: 'Orbit AI is temporarily unavailable. Please try again or continue manually.' } });
    }
    const payload = await response.json() as GeminiResponse;
    const text = payload.candidates?.[0]?.content?.parts?.map((part) => part.text ?? '').join('').trim();
    if (!text) throw new ServiceUnavailableException({ error: { code: 'AI_EMPTY_RESPONSE', message: 'Orbit AI returned no suggestion. Please try again or continue manually.' } });
    try { return JSON.parse(text) as T; }
    catch { throw new ServiceUnavailableException({ error: { code: 'AI_INVALID_RESPONSE', message: 'Orbit AI returned an unreadable suggestion. Please try again or continue manually.' } }); }
  }

  private consumeTrialRequest(userId: string) {
    const day = new Date().toISOString().slice(0, 10);
    const existing = this.usage.get(userId);
    const count = existing?.day === day ? existing.count : 0;
    const dailyLimit = Math.min(100, Math.max(1, Number(process.env.GEMINI_DAILY_LIMIT) || 20));
    if (count >= dailyLimit) throw new HttpException({ error: { code: 'AI_DAILY_LIMIT', message: 'You’ve reached today’s Orbit AI limit. Please try again tomorrow.' } }, 429);
    this.usage.set(userId, { day, count: count + 1 });
  }
}
