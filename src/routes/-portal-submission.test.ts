import { describe, expect, it, vi } from "vitest";

import { preparePortalQuestionSubmission } from "@/routes/-portal-submission";

describe("idempotência do envio de perguntas do portal", () => {
  it("reutiliza a chave no duplo clique e no retry do mesmo envio lógico", () => {
    const createRequestKey = vi.fn().mockReturnValue("portal:key-1");
    const first = preparePortalQuestionSubmission(
      null,
      "case-1",
      "  Minha pergunta fiscal  ",
      createRequestKey,
    );
    const retry = preparePortalQuestionSubmission(
      first,
      "case-1",
      "Minha pergunta fiscal",
      createRequestKey,
    );

    expect(retry).toBe(first);
    expect(retry.clientRequestId).toBe("portal:key-1");
    expect(createRequestKey).toHaveBeenCalledTimes(1);
  });

  it("gera outra chave quando o caso ou o conteúdo mudam", () => {
    const createRequestKey = vi
      .fn()
      .mockReturnValueOnce("portal:key-1")
      .mockReturnValueOnce("portal:key-2")
      .mockReturnValueOnce("portal:key-3");
    const first = preparePortalQuestionSubmission(null, "case-1", "Pergunta A", createRequestKey);
    const changedBody = preparePortalQuestionSubmission(
      first,
      "case-1",
      "Pergunta B",
      createRequestKey,
    );
    const changedCase = preparePortalQuestionSubmission(
      changedBody,
      "case-2",
      "Pergunta B",
      createRequestKey,
    );

    expect(changedBody.clientRequestId).toBe("portal:key-2");
    expect(changedCase.clientRequestId).toBe("portal:key-3");
    expect(createRequestKey).toHaveBeenCalledTimes(3);
  });

  it("rotaciona a chave depois que o envio anterior é concluído", () => {
    const createRequestKey = vi
      .fn()
      .mockReturnValueOnce("portal:key-1")
      .mockReturnValueOnce("portal:key-2");
    preparePortalQuestionSubmission(null, "case-1", "Pergunta repetível", createRequestKey);
    const nextLogicalSubmission = preparePortalQuestionSubmission(
      null,
      "case-1",
      "Pergunta repetível",
      createRequestKey,
    );

    expect(nextLogicalSubmission.clientRequestId).toBe("portal:key-2");
  });
});
