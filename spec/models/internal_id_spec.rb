require 'spec_helper'

describe InternalId do
  let(:project) { create(:project) }
  let(:usage) { :issues }
  let(:issue) { build(:issue, project: project) }
  let(:scope) { { project: project } }
  let(:init) { ->(s) { s.project.issues.size } }

  context 'validations' do
    it { is_expected.to validate_presence_of(:usage) }
  end

  describe '.generate_next' do
    subject { described_class.generate_next(issue, scope, usage, init) }

    context 'in the absence of a record' do
      it 'creates a record if not yet present' do
        expect { subject }.to change { described_class.count }.from(0).to(1)
      end

      it 'stores record attributes' do
        subject

        described_class.first.tap do |record|
          expect(record.project).to eq(project)
          expect(record.usage).to eq(usage.to_s)
        end
      end

      context 'with existing issues' do
        before do
          create_list(:issue, 2, project: project)
          described_class.delete_all
        end

        it 'calculates last_value values automatically' do
          expect(subject).to eq(project.issues.size + 1)
        end
      end

      context 'with concurrent inserts on table' do
        it 'looks up the record if it was created concurrently' do
          args = { **scope, usage: described_class.usages[usage.to_s] }
          record = double
          expect(described_class).to receive(:find_by).with(args).and_return(nil)    # first call, record not present
          expect(described_class).to receive(:find_by).with(args).and_return(record) # second call, record was created by another process
          expect(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, 'record not unique')
          expect(record).to receive(:increment_and_save!)

          subject
        end
      end
    end

    it 'generates a strictly monotone, gapless sequence' do
      seq = Array.new(10).map do
        described_class.generate_next(issue, scope, usage, init)
      end
      normalized = seq.map { |i| i - seq.min }

      expect(normalized).to eq((0..seq.size - 1).to_a)
    end

    context 'with an insufficient schema version' do
      before do
        described_class.reset_column_information
        expect(ActiveRecord::Migrator).to receive(:current_version).and_return(InternalId::REQUIRED_SCHEMA_VERSION - 1)
      end

      let(:init) { double('block') }

      it 'calculates next internal ids on the fly' do
        val = rand(1..100)

        expect(init).to receive(:call).with(issue).and_return(val)
        expect(subject).to eq(val + 1)
      end
    end
  end

  describe '.track_greatest' do
    let(:value) { 9001 }
    subject { described_class.track_greatest(issue, scope, usage, value, init) }

    context 'in the absence of a record' do
      it 'creates a record if not yet present' do
        expect { subject }.to change { described_class.count }.from(0).to(1)
      end
    end

    it 'stores record attributes' do
      subject

      described_class.first.tap do |record|
        expect(record.project).to eq(project)
        expect(record.usage).to eq(usage.to_s)
        expect(record.last_value).to eq(value)
      end
    end

    context 'with existing issues' do
      before do
        create(:issue, project: project)
        described_class.delete_all
      end

      it 'still returns the last value to that of the given value' do
        expect(subject).to eq(value)
      end
    end

    context 'when value is less than the current last_value' do
      it 'returns the current last_value' do
        described_class.create!(**scope, usage: usage, last_value: 10_001)

        expect(subject).to eq 10_001
      end
    end
  end

  describe '#increment_and_save!' do
    let(:id) { create(:internal_id) }
    subject { id.increment_and_save! }

    it 'returns incremented iid' do
      value = id.last_value

      expect(subject).to eq(value + 1)
    end

    it 'saves the record' do
      subject

      expect(id.changed?).to be_falsey
    end

    context 'with last_value=nil' do
      let(:id) { build(:internal_id, last_value: nil) }

      it 'returns 1' do
        expect(subject).to eq(1)
      end
    end
  end

  describe '#track_greatest_and_save!' do
    let(:id) { create(:internal_id) }
    let(:new_last_value) { 9001 }
    subject { id.track_greatest_and_save!(new_last_value) }

    it 'returns new last value' do
      expect(subject).to eq new_last_value
    end

    it 'saves the record' do
      subject

      expect(id.changed?).to be_falsey
    end

    context 'when new last value is lower than the max' do
      it 'does not update the last value' do
        id.update!(last_value: 10_001)

        subject

        expect(id.reload.last_value).to eq 10_001
      end
    end
  end
end
