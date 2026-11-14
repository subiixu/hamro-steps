// The slice of Node's `node:http2` that `pushNode.ts` uses. The project has no
// @types/node (see env.d.ts); drop this file if it ever adds them.
declare module "node:http2" {
  type IncomingHeaders = Record<string, string | string[] | number | undefined>;
  interface ClientHttp2Stream {
    on(event: "response", listener: (headers: IncomingHeaders) => void): this;
    on(event: "data", listener: (chunk: string) => void): this;
    on(event: "end", listener: () => void): this;
    on(event: "error", listener: (err: Error) => void): this;
    setEncoding(encoding: "utf8"): this;
    setTimeout(ms: number, callback: () => void): void;
    close(code?: number): void;
    end(data?: string): void;
  }
  interface ClientHttp2Session {
    request(headers: Record<string, string>): ClientHttp2Stream;
    on(event: "error", listener: (err: Error) => void): this;
    close(): void;
    readonly closed: boolean;
    readonly destroyed: boolean;
  }
  export function connect(authority: string): ClientHttp2Session;
  export const constants: { NGHTTP2_CANCEL: number };
}
