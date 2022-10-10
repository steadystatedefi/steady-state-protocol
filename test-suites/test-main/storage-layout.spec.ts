import { expect } from 'chai';

import { Factories } from '../../helpers/contract-types';
import { DRE } from '../../helpers/dre';
import { NamedDeployable } from '../../helpers/factory-wrapper';
import { ContractStorageLayout, extractContractLayout, isInheritedStorageLayout } from '../../helpers/storage-layout';

import { makeSuite } from './setup/make-suite';

makeSuite('Storage Layouts', () => {
  const getLayout = async (f: NamedDeployable): Promise<ContractStorageLayout> => {
    const n = f.toString();
    const c = await extractContractLayout(DRE, [n]);
    expect(c.length, `Storage layout is missing for ${n}`).gt(0);
    expect(c[0].name).eq(n);
    return c[0];
  };

  it('Imperpetual pool layout', async () => {
    const joinExt = await getLayout(Factories.JoinablePoolExtension);
    const coreExt = await getLayout(Factories.ImperpetualPoolExtension);
    const impl = await getLayout(Factories.ImperpetualPoolV1);
    const wrong = await getLayout(Factories.MockPerpetualPool);

    expect(isInheritedStorageLayout(wrong, impl), 'Storage layout check is broken').eq(false);

    expect(isInheritedStorageLayout(joinExt, coreExt)).eq(true);
    expect(isInheritedStorageLayout(coreExt, impl)).eq(true);
  });
});
