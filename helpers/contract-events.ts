import { TokenSwappedEvent } from '../types/contracts/premium/mocks/MockBalancerLib2';
import { TransferEvent } from '../types/contracts/tools/tokens/ERC20Base';

import { addNamedEvent, EventFactory, wrap } from './event-wrapper';

const stub = null as unknown;

export const Events = {
  TokenSwapped: wrap(stub as TokenSwappedEvent),
  Transfer: wrap(stub as TransferEvent),
};

Object.entries(Events).forEach(([name, factory]) => addNamedEvent(factory, name));

export const eventByName = (s: string): EventFactory => Events[s] as EventFactory;
