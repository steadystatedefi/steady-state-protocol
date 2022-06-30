import { expect } from 'chai';
import { ContractReceipt, ContractTransaction, Event } from 'ethers';
import { Result } from 'ethers/lib/utils';

import { TypedEvent } from '../types/common';

function eventArg(name: string, receipt: ContractReceipt): unknown {
  const found = eventsArg(name, receipt);
  expect(found.length, 'Only one event expected').equals(1);
  return found[0];
}

function eventsArg(name: string, receipt: ContractReceipt): unknown[] {
  const availableEvents = receiptEvents(receipt);
  const found: Result[] = [];

  for (let i = 0; i < availableEvents.length; i++) {
    if (availableEvents[i]?.event === name) {
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      found.push(availableEvents[i].args!);
    }
  }

  expect(found.length, `Failed to find any event matching name: ${name}`).is.greaterThan(0);

  return found;
}

function receiptEvents(receipt: ContractReceipt): Event[] {
  // eslint-disable-next-line no-unused-expressions
  expect(receipt.events, 'No receipt events').is.not.undefined;
  const availableEvents = receipt.events;
  // eslint-disable-next-line no-unused-expressions
  expect(availableEvents, 'Receipt events are undefined').is.not.undefined;
  return availableEvents || [];
}

export type ContractReceiptSource =
  | ContractReceipt
  | Promise<ContractReceipt>
  | ContractTransaction
  | Promise<ContractTransaction>;

export interface EventFactory<TArgObj = unknown> {
  one(receipt: ContractReceipt | ContractTransaction): TArgObj;
  many(receipt: ContractReceipt): TArgObj[];

  waitOne(source: ContractReceiptSource): Promise<TArgObj>;
  waitMany(source: ContractReceiptSource): Promise<TArgObj[]>;

  waitOneWithReceipt(source: ContractReceiptSource): Promise<{ args: TArgObj; receipt: ContractReceipt }>;
  waitManyWithReceipt(source: ContractReceiptSource): Promise<{ args: TArgObj[]; receipt: ContractReceipt }>;

  waitOneAndUnwrap(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt>;
  waitManyAndUnwrap(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt>;

  toString(): string;
  name(): string | undefined;
}

async function receiptOf(av: ContractReceiptSource): Promise<ContractReceipt> {
  const v = await av;
  return 'gasUsed' in v ? v : v.wait(1);
}

const nameByFactory = new Map<EventFactory, string>();

export const wrap = <TArgList extends unknown[], TArgObj>(
  template: TypedEvent<TArgList, TArgObj>,
  customName?: string
): EventFactory<TArgObj> =>
  new (class implements EventFactory<TArgObj> {
    one(receipt: ContractReceipt): TArgObj {
      return eventArg(this.toString(), receipt) as TArgObj;
    }

    unwrapOne<Result>(receipt: ContractReceipt, fn: (args: TArgObj) => Result): Result {
      return fn(this.one(receipt));
    }

    many(receipt: ContractReceipt): TArgObj[] {
      return eventsArg(this.toString(), receipt) as TArgObj[];
    }

    unwrapMany<Result>(receipt: ContractReceipt, fn: (args: TArgObj) => Result): Result[] {
      const result: Result[] = [];
      this.many(receipt).forEach((v) => result.push(fn(v)));
      return result;
    }

    async waitOne(source: ContractReceiptSource): Promise<TArgObj> {
      const receipt = await receiptOf(source);
      return this.one(receipt);
    }

    async waitMany(source: ContractReceiptSource): Promise<TArgObj[]> {
      const receipt = await receiptOf(source);
      return this.many(receipt);
    }

    async waitOneWithReceipt(source: ContractReceiptSource): Promise<{ args: TArgObj; receipt: ContractReceipt }> {
      const receipt = await receiptOf(source);
      return { args: this.one(receipt), receipt } as const;
    }

    async waitManyWithReceipt(source: ContractReceiptSource): Promise<{ args: TArgObj[]; receipt: ContractReceipt }> {
      const receipt = await receiptOf(source);
      return { args: this.many(receipt), receipt } as const;
    }

    async waitOneAndUnwrap(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt> {
      const receipt = await receiptOf(source);
      this.unwrapOne(receipt, fn);
      return receipt;
    }

    async waitManyAndUnwrap(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt> {
      const receipt = await receiptOf(source);
      this.unwrapMany(receipt, fn);
      return receipt;
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string | undefined {
      return customName ?? nameByFactory.get(this);
    }
  })();

export const addNamedEvent = (f: EventFactory, name: string): void => {
  nameByFactory.set(f, name);
};
